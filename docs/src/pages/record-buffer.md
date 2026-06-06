---
layout: ../layouts/DocsLayout.astro
title: RecordBuffer | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock RecordBuffer Apex utility.
eyebrow: Automation
heading: RecordBuffer
lede: A static, transaction-scoped staging area that collects SObject records as your trigger logic runs and writes them to the database in one grouped upsert per object type when you flush — so each unit of work issues the fewest possible DML statements.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Examples
    href: "#examples"
  - label: Contexts & Nested Flushes
    href: "#contexts-and-nested-flushes"
  - label: Reading Staged Records
    href: "#reading-staged-records"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`RecordBuffer` is a **static staging area** for SObject records. Instead of
running `update` or `insert` the moment a piece of logic decides a record needs
saving, you hand the record to the buffer. The buffer holds it in memory, and
when you call `flush()` it writes everything it has collected — grouped by
object type — in as few DML statements as possible.

The pattern it implements is **Unit of Work**: collect all the changes that
belong to one logical operation, then commit them together at the end. In a
Salesforce trigger that matters because DML statements are a governor limit
(150 per transaction). If five different trigger handlers each want to update
the same Account, five separate `update` calls is wasteful — and, in a
recursive trigger, dangerous. The buffer turns those five intentions into one
upsert.

**Use `RecordBuffer` when** several independent pieces of logic in the same
transaction produce records to save, and you want to consolidate them into one
grouped write — classic trigger-context staging, where handlers stage records
and a single point flushes them.

**Reach for direct DML instead when** you genuinely need the write to happen
*now* — for example because later logic in the same transaction must re-query
the saved row, or because you need the inserted Ids immediately. The buffer
defers the write until `flush()`, so anything that depends on the write having
already happened should not go through it.

> **It is static.** There is no `new RecordBuffer()`. Everything is reached
> through `RecordBuffer.put(...)`, `RecordBuffer.get(...)`, and
> `RecordBuffer.flush()`. The staged records live in static state for the life
> of the transaction. Read [Gotchas](#gotchas-and-testing-notes) before relying
> on that.

## How It Works

Three ideas explain everything `RecordBuffer` does.

### 1. Insert vs. update is decided by the Id

When you `put` a record, the buffer inspects its `Id`:

- **No `Id`** → it is staged as an **insert**, appended to a per-type
  `List<SObject>`.
- **Has an `Id`** → it is staged as an **update**, placed in a per-type
  `Map<Id, SObject>` keyed by Id.

Because updates are keyed by Id, **staging the same Id twice keeps only the
last version** — the map overwrites. That deduping is deliberate: if two
handlers each touch Account `001...`, the buffer commits one record with the
most recently staged field values, not two competing updates.

### 2. `flush()` groups by object type and upserts

`flush()` merges the staged inserts and staged updates back together per
`SObjectType`, then issues **one `DML.upsertRecords(...)` call per object
type**. Mixing inserts and updates into a single `upsert` is exactly why the
buffer can save a heterogeneous batch in one statement per type: `upsert`
inserts the rows with no Id and updates the rows that have one.

So if a context holds 3 Accounts and 5 Contacts, `flush()` issues two DML
calls (one Account upsert, one Contact upsert) — not eight.

> The buffer commits through the sf-bedrock `DML` facade
> (`DML.upsertRecords`), not raw `upsert` DML. That is what lets tests swap in
> a `DMLMock` and assert on what *would* have been written without touching the
> database — see [Gotchas & Testing Notes](#gotchas-and-testing-notes).

### 3. State is a stack of contexts

The buffer does not hold one bucket of records — it holds a **stack** (a
`List`) of `TriggerContext` objects. `start()` pushes a fresh context onto the
stack; `flush()` operates on the **top** (most recently started) context and
then pops it off. `put` and `get` always target the current top context.

This stack is what makes the buffer safe under **recursion and nesting**: an
inner unit of work can `start()` its own context, do its staging, and `flush()`
it without disturbing records the outer unit of work already staged. See
[Contexts & Nested Flushes](#contexts-and-nested-flushes).

If you `put` or `flush` without ever calling `start()`, the buffer **lazily
creates** a context for you, so the simple "stage then flush" path just works.

## Public API

`RecordBuffer` exposes only **static** methods. There are no public
constructors and no instance entry points — you never instantiate it.

> **A note on "properties":** `RecordBuffer` has **no public properties**. Its
> entire state — the `contexts` stack and the per-context `inserts`/`updates`
> maps — is held in static and instance fields you reach only through the
> methods below. (The inner `TriggerContext` class does expose public
> `inserts`/`updates` maps, but `TriggerContext` is an implementation detail you
> are not expected to construct or touch directly.)

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `start` | `start()` | `void` | Pushes a new, empty context onto the stack. Use it to open a nested unit of work. Optional for the simple case — `put`/`flush` auto-start a context if none exists. |
| `put` | `put(SObject record)` | `void` | Stages one record in the current context. A record with no `Id` is staged as an insert; a record with an `Id` is staged as an update (deduped by Id). `null` is ignored. |
| `put` | `put(List<SObject> records)` | `void` | Stages each record in the list (skipping any `null` elements). A `null` list is ignored. |
| `put` | `put(Map<Id, SObject> recordsById)` | `void` | Stages every value in the map. A `null` map is ignored. |
| `put` | `put(Id recordId)` | `SObject` | **Read accessor, not a stage.** Returns the staged record for that Id, or a skeletal SObject of the right type carrying just the Id if nothing is staged. Returns `null` for a `null` Id. See [Reading Staged Records](#reading-staged-records). |
| `get` | `get(Set<Id> recordIds)` | `List<SObject>` | Returns one entry per Id (each resolved exactly like `put(Id)`). Returns `null` for a `null` or empty set. |
| `flush` | `flush()` | `void` | Upserts everything staged in the current (top) context — one `DML.upsertRecords` call per object type — then removes that context from the stack. Does nothing if the stack is empty. |

> **The `put(Id)` overload is a getter.** It shares the `put` name but it does
> **not** stage anything — it reads. It delegates to the inner context's
> `get(Id)` method. Keep this overload in mind: `RecordBuffer.put(someAccount.Id)`
> returns a record; it does not buffer one.

### Inner types

| Type | Visibility | Role |
| --- | --- | --- |
| `RecordBuffer.TriggerContext` | `public` (inner class) | One unit of work's staging buckets (`inserts`, `updates`) plus its own `put`/`get`/`flush`. The buffer keeps a stack of these. You normally never reference it directly. |
| `RecordBuffer.RecordBufferException` | `public` (extends `Exception`) | A custom exception type declared on the class. |

## Examples

The examples below mirror what the unit tests in `RecordBufferTest` actually
exercise. They build in-memory records with [`TestData`](/test-data) and assert
against a `DMLMock` so no real database write happens.

### Stage records and flush

The everyday shape: open a context, stage records of different types, flush.
One upsert is issued per object type.

```apex
DMLMock dmlMock = new DMLMock();
DML.setMock(dmlMock);

Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Bedrock')
  .build()[0];

Contact contact = (Contact) new TestData(Contact.sObjectType)
  .put(Contact.LastName, 'Lovelace')
  .mockIds()
  .build()[0];

RecordBuffer.start();
RecordBuffer.put(account);   // no Id -> staged as an insert
RecordBuffer.put(contact);   // has an Id -> staged as an update
RecordBuffer.flush();

Assert.areEqual(2, dmlMock.upserts.size(), 'Expected one upsert call per object type staged.');
```

### You can skip `start()`

`put` (and `flush`) lazily create a context when none exists, so the simplest
path needs no explicit `start()`.

```apex
Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Auto Start')
  .build()[0];

RecordBuffer.put(account);   // context created on demand
RecordBuffer.flush();        // upserts the auto-started context

Assert.areEqual(1, dmlMock.upserts.size(), 'Expected put() to lazily create a context.');
```

### Stage a list (nulls are dropped)

`put(List<SObject>)` walks the list and stages each non-null element. A `null`
member is silently skipped; a `null` list is ignored entirely.

```apex
Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Only Real Record')
  .build()[0];

RecordBuffer.start();
RecordBuffer.put(new List<SObject>{ null, account });
RecordBuffer.flush();

Assert.areEqual(1, dmlMock.upserts.size(), 'Expected one upsert when one non-null record is staged.');
Assert.areEqual(1, dmlMock.upserts[0].size(), 'Expected only the non-null list member to be staged.');
```

### Updates dedupe by Id — last write wins

Stage two versions of the same record (same Id) and only one survives the flush:
the most recently staged field values.

```apex
Account original = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Original')
  .mockIds()
  .build()[0];

Account updated = (Account) original.clone(true, false, false, false);
updated.Name = 'Latest';

RecordBuffer.start();
RecordBuffer.put(original);
RecordBuffer.put(updated);   // same Id -> overwrites the previous stage
RecordBuffer.flush();

Assert.areEqual(1, dmlMock.upserts[0].size(), 'Expected one record after deduping updates by Id.');
Assert.areEqual('Latest', ((Account) dmlMock.upserts[0][0]).Name, 'Expected the latest staged update to win.');
```

### Null inputs are safe

Every staging overload tolerates `null` — no exception, nothing staged.

```apex
RecordBuffer.start();
RecordBuffer.put((SObject) null);
RecordBuffer.put((List<SObject>) null);
RecordBuffer.put((Map<Id, SObject>) null);
RecordBuffer.flush();

Assert.areEqual(0, dmlMock.upserts.size(), 'Expected null inputs to stage nothing and produce no DML.');
```

## Contexts & Nested Flushes

A **context** is one unit of work's staging bucket. The buffer keeps a stack of
them so that nested operations don't trample each other. The rules are:

- `start()` pushes a **new empty context** onto the top of the stack.
- `put` and `get` always target the **top** (current) context.
- `flush()` processes the **top** context, then **pops it off** — exposing the
  context beneath it as the new top.

This is last-in, first-out. If an outer process starts a context and stages a
record, then an inner process starts its own context and stages another, the
**first** `flush()` commits the inner records (it is on top) and the **second**
`flush()` commits the outer records.

```apex
Account outer = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Outer').build()[0];
Account inner = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Inner').build()[0];

RecordBuffer.start();            // outer context pushed
RecordBuffer.put(outer);

RecordBuffer.start();            // inner context pushed (now on top)
RecordBuffer.put(inner);

RecordBuffer.flush();            // flushes the inner context first
Assert.areEqual('Inner', ((Account) dmlMock.upserts[0][0]).Name, 'Inner context flushes first.');

RecordBuffer.flush();            // flushes the outer context next
Assert.areEqual('Outer', ((Account) dmlMock.upserts[1][0]).Name, 'Outer context flushes after inner is removed.');
```

> **Balance your `start()` and `flush()` calls.** Each `start()` adds a context
> that only a matching `flush()` removes. If you `start()` more than you
> `flush()`, the leftover contexts (and their staged records) are never written
> for the rest of the transaction. If you `flush()` an empty stack it is a
> no-op, so an extra `flush()` is harmless — an extra `start()` is not.

## Reading Staged Records

The buffer is not just a write sink — it can answer "what does this record look
like *right now*, including changes staged but not yet flushed?" That is what
the `put(Id)` getter and `get(Set<Id>)` are for. This lets logic later in the
same context see the not-yet-committed version of a record instead of querying a
stale copy from the database.

Resolution rules for a single Id:

1. **`null` Id** → returns `null`.
2. **Id staged as an update** → returns the staged record, with its staged
   field values.
3. **Id not staged** → returns a **skeletal** SObject of the correct type
   (derived from the Id's key prefix) carrying only that `Id` — every other
   field is `null`.

```apex
Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Buffered Update')
  .mockIds()
  .build()[0];

RecordBuffer.start();
RecordBuffer.put(account);

// Known Id -> the staged record comes back with its staged values
Account hit = (Account) RecordBuffer.put(account.Id);
Assert.areEqual('Buffered Update', hit.Name, 'Expected the staged values for a known Id.');

// Unknown Id -> a skeleton with just the Id
Account other = (Account) new TestData(Account.sObjectType).mockIds().build()[0];
Account miss = (Account) RecordBuffer.put(other.Id);
Assert.areEqual(other.Id, miss.Id, 'Expected a skeleton carrying just the Id.');
Assert.isNull(miss.Name, 'Expected an unstaged skeleton to have no field values.');
```

`get(Set<Id>)` is the bulk version — one resolved entry per Id, in iteration
order. A `null` or empty set returns `null` (not an empty list), so guard for
that:

```apex
RecordBuffer.start();

Assert.isNull(RecordBuffer.get((Set<Id>) null), 'Expected null for a null Id set.');
Assert.isNull(RecordBuffer.get(new Set<Id>()), 'Expected null for an empty Id set.');
```

> **Reads only see staged *updates*, not staged *inserts*.** The getter resolves
> Ids against the `updates` map. Records you staged without an Id (inserts) have
> no Id to look up, so the getter cannot return them. An Id that was never
> staged as an update always yields a skeleton, never an error.

## Gotchas & Testing Notes

- **`put(Id)` reads, it does not stage.** Despite the name, the `Id` overload is
  a getter that returns a record. Only the `SObject` / `List` / `Map` overloads
  stage. Don't confuse `RecordBuffer.put(record)` (stages) with
  `RecordBuffer.put(record.Id)` (reads).

- **Writes are deferred until `flush()`.** Nothing hits the database when you
  `put`. If later logic in the same transaction must re-query the saved row or
  needs the new Ids, the buffer is the wrong tool — use direct DML there.

- **Updates dedupe; inserts don't.** Two stages of the same Id collapse to one
  (last wins). Two `Id`-less records of the same type are two separate inserts —
  the buffer has no key to dedupe them on.

- **State is static and transaction-scoped.** The `contexts` stack is a static
  field, so staged records persist across method calls within one transaction.
  Each new transaction starts empty. Be deliberate about who flushes, so records
  aren't left staged at the end of the transaction.

- **Balance `start()` with `flush()`.** Every `start()` needs a matching
  `flush()` to be written. Unflushed contexts are silently dropped at the end of
  the transaction. `flush()` on an empty stack is a harmless no-op.

- **One upsert per object type, not per record.** That is the whole point —
  grouped flush keeps you well inside the 150-DML-statement governor limit even
  when many handlers stage records. But each object type still costs one DML
  statement, so flushing N distinct types issues N statements.

- **`flush()` uses `upsert`.** Inserts and updates for a type are merged into a
  single `upsert`. Make sure any record you stage is genuinely upsertable —
  e.g. don't populate read-only or system fields on records you intend to flush
  (those belong to [`TestData`](/test-data) mocking, not to real DML).

- **Test through the `DML` facade.** Because `flush()` calls
  `DML.upsertRecords(...)`, tests register a `DMLMock` with `DML.setMock(...)`
  and assert on `dmlMock.upserts` — a `List<List<SObject>>`, one inner list per
  upsert call. `dmlMock.upserts.size()` is the number of DML calls (one per
  object type per flush); each inner list holds the records sent in that call.
  This is how the buffer is unit-tested with no database round-trip.
