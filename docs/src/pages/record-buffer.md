---
layout: ../layouts/DocsLayout.astro
title: RecordBuffer | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock RecordBuffer Apex utility.
eyebrow: Automation
heading: RecordBuffer
lede: A static staging buffer that collects SObject records during a transaction and flushes them as grouped, deduplicated upserts — so trigger-context code can defer and batch its DML instead of writing row by row.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Examples
    href: "#examples"
  - label: Nested Contexts & Flush Order
    href: "#nested-contexts-and-flush-order"
  - label: Reading Staged Records
    href: "#reading-staged-records"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`RecordBuffer` is a transaction-scoped staging area for `SObject` records. Code
spread across a transaction — most often trigger handlers and the services they
call — hands records to the buffer with `put(...)`. The buffer holds them in
memory, grouped by object type, and writes nothing until someone calls
`flush()`. At flush time it issues **one upsert per object type**, after
deduplicating updates by `Id`.

The point is to turn many small, scattered DML operations into a few large,
grouped ones. In a transaction, code in different places frequently wants to
write to the same objects. If each spot runs its own `update`, you burn DML
statements quickly, you can hit the same record more than once, and you risk
re-entrant trigger work. `RecordBuffer` lets every contributor *stage* its
records and lets a single coordinator *flush* them together.

**Use `RecordBuffer` when** several pieces of code in one transaction need to
write records and you want to collapse those writes into grouped, deduplicated
upserts performed at a controlled point — typically the "after" phase of a
trigger, or the end of a service routine.

**Reach for direct DML instead when** you need a single, immediate write with
no staging, when you need ordering between objects that the buffer's grouping
does not give you, or when you need insert/update/delete semantics that are not
an upsert (the buffer only ever upserts — see [How It Works](#how-it-works)).

> `RecordBuffer` does not register itself with the platform. Nothing flushes the
> buffer automatically — **you must call `flush()` yourself**. Records you stage
> and never flush are simply discarded at the end of the transaction.

## How It Works

Four ideas explain everything `RecordBuffer` does.

### 1. State is static and lives for the transaction

All buffer state hangs off a single private `static` list of contexts:

```apex
static List<TriggerContext> contexts = new List<TriggerContext>();
```

Because it is `static`, the buffer is shared by every caller in the same Apex
transaction — a trigger handler and a service it invokes see the *same* buffer.
Like all Apex static state, it is cleared when the transaction ends; there is no
persistence and no need to "reset" between transactions.

### 2. A context is a unit of staging

Each entry in `contexts` is a `TriggerContext`: a pair of maps that hold the
records staged so far.

```apex
public Map<SObjectType, List<SObject>> inserts;        // records with no Id
public Map<SObjectType, Map<Id, SObject>> updates;     // records with an Id, keyed by Id
```

When you `put` a record, the context routes it by whether it already has an `Id`:

- **No `Id`** → appended to the `inserts` list for that object type.
- **Has an `Id`** → placed in the `updates` map for that object type, keyed by
  `Id`. Because it is a map, **staging the same `Id` twice keeps the last one**
  — that is the dedupe behavior.

Calling `RecordBuffer.start()` pushes a brand-new context onto the list. You do
not have to call it: any `put`/`get`/`flush` that finds an empty list lazily
calls `start()` for you (see [Nested Contexts](#nested-contexts-and-flush-order)
for when you *do* want to call it explicitly).

### 3. Flush groups everything into one upsert per object type

`flush()` operates on the **current** (most recently started) context. It merges
that context's `inserts` and `updates` back together per object type, then calls
`DML.upsertRecords(...)` once for each object type:

```apex
for (SObjectType sObjectType : upserts.keySet()) {
    List<SObject> records = upserts.get(sObjectType);
    DML.upsertRecords(records);
}
```

The DML verb is always **upsert**. Records without an `Id` are inserted; records
with an `Id` are updated — that is exactly what `upsert` does, which is why the
buffer can mix both in one call. After flushing, the current context is removed
from the list, so its staged records cannot be flushed again.

> Two object types means two `upsert` calls, three means three, and so on. The
> buffer groups by `SObjectType` to keep each DML statement homogeneous, but it
> does **not** combine different object types into a single statement.

### 4. DML goes through the `DML` service (mockable)

The buffer never writes with a raw `upsert` keyword. It delegates to
`DML.upsertRecords(...)`, the project's swappable DML service. In tests you
install a `DMLMock` and assert on what *would* have been written, with no real
database access. Every example below relies on this.

## Public API

`RecordBuffer` exposes a set of `static` methods plus one public inner class,
`TriggerContext`. The static methods are the supported entry point; they all
operate on the current context.

> **A note on "properties":** `RecordBuffer` itself has **no public properties**.
> Its only state — the `static` `contexts` list — is **private** (it has no
> access modifier, and in Apex no modifier means `private`). You interact with it
> exclusively through the static methods below. The `currentContext()` and
> `currentContextPosition()` helpers are likewise private and not part of the
> surface.

### Static methods

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `start` | `start()` | `void` | Pushes a new, empty `TriggerContext` onto the stack and makes it current. Optional — `put`/`get`/`flush` auto-start a context if none exists. Call it explicitly to open a nested scope (see [Nested Contexts](#nested-contexts-and-flush-order)). |
| `put` | `put(SObject record)` | `void` | Stages one record into the current context. `null` is ignored. No `Id` → staged for insert; has an `Id` → staged for update, keyed by `Id`. |
| `put` | `put(List<SObject> records)` | `void` | Stages each element via the single-record `put`. `null` list is ignored; `null` elements within the list are skipped. |
| `put` | `put(Map<Id, SObject> recordsById)` | `void` | Stages `recordsById.values()`. `null` map is ignored. |
| `put` | `put(Id recordId)` | `SObject` | **This overload is a getter, not a setter.** It returns the staged record for `recordId`, or a skeletal SObject of the right type carrying just that `Id` if nothing is staged. Returns `null` for a `null` Id. See [Reading Staged Records](#reading-staged-records). |
| `get` | `get(Set<Id> recordIds)` | `List<SObject>` | Returns one element per requested Id (staged record or skeleton), in iteration order. Returns `null` for a `null` or empty set. |
| `flush` | `flush()` | `void` | Upserts the current context's records — one grouped, deduplicated `DML.upsertRecords` call per object type — then removes that context. A no-op if no context exists. |

> **Watch the overload:** `put(Id)` reads; the other `put(...)` overloads write.
> The shared name is convenient at the call site but easy to misread. When you
> mean "fetch," prefer thinking of it as a get — the inner `TriggerContext`
> exposes the same logic as `get(Id)`.

### Inner class: `TriggerContext`

`TriggerContext` is `public`, so it is technically part of the surface, but the
static façade exists precisely so you rarely touch it directly. It holds the
staging maps and implements the real `put`/`get`/`flush` logic the static
methods delegate to.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `TriggerContext()` | `TriggerContext` | Creates empty `inserts` and `updates` maps. |
| `inserts` (property) | `Map<SObjectType, List<SObject>>` | — | Records staged for insert (no `Id`), grouped by object type. |
| `updates` (property) | `Map<SObjectType, Map<Id, SObject>>` | — | Records staged for update (have an `Id`), grouped by object type then keyed by `Id`. |
| `put` | `put(SObject)` / `put(List<SObject>)` / `put(Map<Id, SObject>)` | `void` | Same staging rules as the static overloads. |
| `get` | `get(Id)` | `SObject` | Returns the staged record for the Id, or a `sObjectType.newSObject(recordId)` skeleton if not staged; `null` for a `null` Id. |
| `get` | `get(Set<Id>)` | `List<SObject>` | One `get(Id)` result per Id; `null` for a `null`/empty set. |
| `flush` | `flush()` | `void` | Merges this context's `inserts` and `updates` and upserts one grouped list per object type. Does **not** remove itself from the stack — only the static `flush()` does that. |

The private helpers `stageInsert` and `stageUpdate` (no access modifier) are
implementation details, not API.

### `RecordBufferException`

`RecordBuffer` declares a `public class RecordBufferException extends Exception`.
It exists as a typed exception for callers/extensions, but the current code
**never throws it**. Do not write `catch (RecordBuffer.RecordBufferException e)`
expecting the buffer to raise it on its own.

## Examples

All examples install a `DMLMock` so they run without touching the database. The
mock records each `upsertRecords` call as one entry in `dmlMock.upserts`, so
`dmlMock.upserts.size()` is the number of upsert statements and
`dmlMock.upserts[n]` is the record list for the nth statement.

### Stage two object types, flush once

Each object type becomes its own grouped upsert. Here an Account (no Id → insert)
and a Contact (mock Id → update) stage and flush together.

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
RecordBuffer.put(account);
RecordBuffer.put(contact);
RecordBuffer.flush();

Assert.areEqual(2, dmlMock.upserts.size(), 'Expected one upsert call per object type.');
Assert.areEqual(1, dmlMock.upserts[0].size(), 'Expected one record in the first call.');
Assert.areEqual(1, dmlMock.upserts[1].size(), 'Expected one record in the second call.');
```

### Auto-started context (no explicit `start()`)

`start()` is optional. The first `put` lazily opens a context, and `flush()`
processes it.

```apex
DMLMock dmlMock = new DMLMock();
DML.setMock(dmlMock);

Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Auto Start')
  .build()[0];

RecordBuffer.put(account);   // no start() called first
RecordBuffer.flush();

Assert.areEqual(1, dmlMock.upserts.size(), 'Expected put() to lazily create a context.');
Assert.areEqual(1, dmlMock.upserts[0].size(), 'Expected the staged record to flush.');
```

### Dedupe updates by Id (last write wins)

Two records with the **same Id** collapse to one. Updates are kept in a map keyed
by `Id`, so the most recently staged version wins.

```apex
DMLMock dmlMock = new DMLMock();
DML.setMock(dmlMock);

Account original = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Original')
  .mockIds()
  .build()[0];

Account updated = (Account) original.clone(true, false, false, false);
updated.Name = 'Latest';

RecordBuffer.start();
RecordBuffer.put(original);
RecordBuffer.put(updated);   // same Id as original
RecordBuffer.flush();

Assert.areEqual(1, dmlMock.upserts.size(), 'Expected a single upsert for one object type.');
Assert.areEqual(1, dmlMock.upserts[0].size(), 'Expected one record after dedupe by Id.');
Assert.areEqual('Latest', ((Account) dmlMock.upserts[0][0]).Name, 'Expected the latest value to win.');
```

> Dedupe applies only to records with an `Id` (the update path). Records with no
> `Id` go into a `List` and are **not** deduplicated — stage the same new record
> twice and it will be inserted twice.

### Stage a list, with nulls ignored

`put(List<SObject>)` skips `null` elements and stages the rest. A `null` list,
single `null`, or `null` map are all ignored without error.

```apex
DMLMock dmlMock = new DMLMock();
DML.setMock(dmlMock);

Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Only Real Record')
  .build()[0];

RecordBuffer.start();
RecordBuffer.put(new List<SObject>{ null, account });   // null skipped
RecordBuffer.put((SObject) null);                       // ignored
RecordBuffer.put((Map<Id, SObject>) null);              // ignored
RecordBuffer.flush();

Assert.areEqual(1, dmlMock.upserts.size(), 'Expected one upsert for the single real record.');
Assert.areEqual('Only Real Record', ((Account) dmlMock.upserts[0][0]).Name, 'Expected values preserved.');
```

### A trigger-context shape

The realistic pattern: a handler stages records as it processes them, then a
single `flush()` performs all the grouped DML at the end.

```apex
public class AccountTriggerHandler {
  public void afterUpdate(List<Account> accounts) {
    RecordBuffer.start();

    for (Account a : accounts) {
      Contact rollupContact = buildRollupContact(a);   // may have an Id (update) or not (insert)
      RecordBuffer.put(rollupContact);
      RecordBuffer.put(a);                              // re-stage the account too
    }

    RecordBuffer.flush();   // one grouped upsert per object type, deduped by Id
  }
}
```

Because the buffer dedupes by `Id`, two handlers that both stage the same
record in the same transaction produce a single write of the last version,
rather than two conflicting updates.

## Nested Contexts & Flush Order

`start()` pushes a new context; `flush()` processes and pops the **current**
(top) one. Calling `start()` again before flushing creates a **stack** of
contexts, and the buffer is a last-in, first-out (LIFO) stack: the most recently
started context flushes first, and each `flush()` peels one off.

This is the "trigger-context" part of the design. If staging code triggers more
work that itself wants to stage and flush independently, the inner scope can
`start()` its own context, do its work, and `flush()` — without disturbing the
records the outer scope already staged.

```apex
DMLMock dmlMock = new DMLMock();
DML.setMock(dmlMock);

Account outer = (Account) new TestData(Account.sObjectType).put(Account.Name, 'Outer').build()[0];
Account inner = (Account) new TestData(Account.sObjectType).put(Account.Name, 'Inner').build()[0];

RecordBuffer.start();          // outer context
RecordBuffer.put(outer);
RecordBuffer.start();          // inner context (now current)
RecordBuffer.put(inner);

RecordBuffer.flush();          // flushes INNER first, then pops it
Assert.areEqual(1, dmlMock.upserts.size(), 'Expected the first flush to handle only the inner context.');
Assert.areEqual('Inner', ((Account) dmlMock.upserts[0][0]).Name, 'Expected inner records first.');

RecordBuffer.flush();          // now flushes OUTER
Assert.areEqual(2, dmlMock.upserts.size(), 'Expected the second flush to handle the outer context.');
Assert.areEqual('Outer', ((Account) dmlMock.upserts[1][0]).Name, 'Expected outer records second.');
```

> **Balance your calls.** Each `start()` you make should be matched by a
> `flush()`. An unmatched `start()` leaves a context staged but never written; an
> extra `flush()` on an empty stack is a harmless no-op. If you open a nested
> context, flush it before expecting the outer context to be the one acted upon —
> `put`/`flush` always target the **top** of the stack.

> **Recursion-mindful usage.** Because flush issues real DML (upserts), it can
> re-enter triggers. Nesting contexts lets inner work flush in isolation, but it
> does not by itself stop trigger recursion — pair the buffer with whatever
> recursion guard your trigger framework provides so an inner flush does not
> loop back into the same handler indefinitely.

## Reading Staged Records

Besides staging, the buffer lets you **read what is currently staged** for a
given `Id` — useful when later code in the same transaction needs the
in-progress version of a record rather than re-querying the database.

`put(Id)` (the getter overload) and `get(Set<Id>)` behave like this:

- **Id is staged as an update** → you get the staged record, with its staged
  field values.
- **Id is not staged** → you get a fresh skeleton, `sObjectType.newSObject(id)`:
  a record of the right type carrying only that `Id`, with all other fields
  `null`.
- **`null` Id** → `null`. **`null` or empty `Set<Id>`** → `null`.

### Read a staged update

```apex
Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Buffered Update')
  .mockIds()
  .build()[0];

RecordBuffer.start();
RecordBuffer.put(account);

Account result = (Account) RecordBuffer.put(account.Id);   // getter overload

Assert.areEqual(account.Id, result.Id, 'Expected the staged record back for a known Id.');
Assert.areEqual('Buffered Update', result.Name, 'Expected staged field values.');
```

### Read an Id that was never staged

```apex
Account account = (Account) new TestData(Account.sObjectType)
  .mockIds()
  .build()[0];

RecordBuffer.start();
Account result = (Account) RecordBuffer.put(account.Id);   // nothing staged for this Id

Assert.areEqual(account.Id, result.Id, 'Expected a skeleton carrying just the requested Id.');
Assert.areEqual(null, result.Name, 'Expected an unstaged skeleton to have no field values.');
```

> The skeleton means a "miss" never returns `null` for a real Id — you always get
> a usable SObject of the correct type. Check whether a field is populated (not
> whether the result is `null`) to tell a staged hit from a skeleton miss.

### Read several Ids at once

```apex
RecordBuffer.start();

SObject byNullId  = RecordBuffer.put((Id) null);          // null
List<SObject> byNullSet  = RecordBuffer.get((Set<Id>) null);   // null
List<SObject> byEmptySet = RecordBuffer.get(new Set<Id>());    // null

Assert.areEqual(null, byNullId, 'Expected null for a null Id.');
Assert.areEqual(null, byNullSet, 'Expected null for a null set.');
Assert.areEqual(null, byEmptySet, 'Expected null for an empty set.');
```

> `get(Set<Id>)` only reads — it looks records up by `Id` against the `updates`
> map. It never reads from the `inserts` side, because insert-staged records have
> no `Id` to look up by.

## Gotchas & Testing Notes

- **Nothing flushes for you.** The buffer registers no hook with the platform.
  If you never call `flush()`, your staged records are silently dropped when the
  transaction ends. Always pair staging with a flush.

- **`put(Id)` is a getter.** It is the odd one out: the other `put` overloads
  stage records and return `void`; `put(Id)` returns an `SObject`. Read it as
  "get the staged record for this Id."

- **Only upserts.** The buffer's single DML verb is `upsert`. It cannot delete,
  and it cannot force insert-vs-update beyond what the presence of an `Id`
  implies. If you need delete/undelete or strict insert/update, use the `DML`
  service directly.

- **Dedupe is update-only.** Records with an `Id` dedupe by `Id` (last write
  wins). Records without an `Id` accumulate in a list and are not deduplicated —
  stage the same new record twice and it inserts twice.

- **One upsert statement per object type.** N object types in a context means N
  DML statements at flush. Group flushes deliberately so you stay within the
  150-DML-statements governor limit; staging many types and flushing them all at
  once still costs one statement each.

- **State is static and transaction-scoped.** All callers in a transaction share
  the same buffer, which is the feature — but it also means leftover staged
  records from earlier in the same transaction will be flushed too. In tests,
  each test method runs in its own transaction, so the buffer starts empty.

- **Mind the context stack.** `start()` and `flush()` are LIFO. Unbalanced
  `start()` calls leave contexts unflushed; `put`/`flush` always act on the top
  of the stack. An extra `flush()` on an empty stack is a safe no-op.

- **`RecordBufferException` is never thrown** by the current code. Do not rely on
  catching it for buffer errors.

- **Testing pattern: install a `DMLMock`.** Call `DML.setMock(new DMLMock())`,
  exercise the buffer, then assert against `dmlMock.upserts`. `upserts.size()`
  counts statements (one per object type per flush) and `upserts[n]` holds the
  records of the nth statement. Build the staged records with `TestData`
  (`.mockIds()` when you need the update path) so no real DML is required.
