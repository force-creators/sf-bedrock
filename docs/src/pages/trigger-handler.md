---
layout: ../layouts/DocsLayout.astro
title: TriggerHandler | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock TriggerHandler Apex base class.
eyebrow: Automation
heading: TriggerHandler
lede: A lightweight base class that reads the running trigger's context, routes it to the right before/after hook, and wraps the whole dispatch in a RecordBuffer so your handler can stage DML and have it flushed automatically.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Wiring It Into a Trigger
    href: "#wiring-it-into-a-trigger"
  - label: Examples
    href: "#examples"
  - label: Buffered DML
    href: "#buffered-dml"
  - label: Testing Without a Trigger
    href: "#testing-without-a-trigger"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`TriggerHandler` is the base class you subclass to handle Apex triggers in
sf-bedrock. It is a small implementation of the **Template Method pattern**: the
base class owns the fixed sequence (check the context, set up buffering, route to
a hook, flush buffering), and you fill in the parts that are specific to your
object by **overriding** the hook methods you care about.

The class solves three problems that every hand-written trigger has to solve:

1. **Context detection** — figuring out which trigger event is running
   (`BEFORE_INSERT`, `AFTER_UPDATE`, and so on) and reading `Trigger.new`,
   `Trigger.old`, `Trigger.newMap`, `Trigger.oldMap` safely.
2. **Dispatch** — calling the right method for that event instead of writing one
   giant `if (Trigger.isBefore && Trigger.isInsert) { ... }` ladder.
3. **DML coordination** — opening a [`RecordBuffer`](#buffered-dml) before your
   logic runs and flushing it afterward, so any records you stage during the hook
   are upserted for you.

**Use `TriggerHandler` when** you want a thin, predictable place to put
trigger logic for an object, with the context already unpacked and DML staging
handled for you.

> This is a deliberately minimal framework. It does **not** ship a built-in
> recursion guard, a metadata-driven enable/disable switch, or per-object
> registration. If you need those, you build them in your subclass — the class
> is `virtual` precisely so you can. See
> [Gotchas & Testing Notes](#gotchas-and-testing-notes).

## How It Works

The whole engine is the `run()` method, which executes four steps in order
every time it is called:

```apex
protected void run() {
    if (!this.isExecuting()) return;   // 1. bail out unless we are in a trigger
    this.stageBuffers();               // 2. open a RecordBuffer context
    this.dispatch();                   // 3. route to the matching hook
    this.flushBuffers();               // 4. upsert everything staged
}
```

### 1. It guards on trigger context

`run()` immediately returns unless `isExecuting()` is `true`. In the base class
`isExecuting()` returns `Trigger.isExecuting`, so calling `run()` from anywhere
that is *not* a trigger (a button action, a batch job, a unit test) does
nothing. That is what makes the handler safe to instantiate anywhere.

### 2. It opens a RecordBuffer

`stageBuffers()` calls `RecordBuffer.start()`, which pushes a fresh buffer
context onto a stack. While your hook runs, anything you hand to
`RecordBuffer.put(...)` is collected but not yet written.

### 3. It dispatches on the operation type

`dispatch()` reads `operationType()` (in the base class, `Trigger.operationType`)
and uses a `switch` to call exactly one hook, passing the records that event
actually provides:

| Operation | Hook called | Arguments passed |
| --- | --- | --- |
| `BEFORE_INSERT` | `beforeInsert` | `newRecords()` |
| `BEFORE_UPDATE` | `beforeUpdate` | `newRecords()`, `oldRecordsById()` |
| `BEFORE_DELETE` | `beforeDelete` | `oldRecords()`, `oldRecordsById()` |
| `AFTER_INSERT` | `afterInsert` | `newRecords()`, `newRecordsById()` |
| `AFTER_UPDATE` | `afterUpdate` | `newRecords()`, `oldRecordsById()`, `newRecordsById()` |
| `AFTER_DELETE` | `afterDelete` | `oldRecords()`, `oldRecordsById()` |
| `AFTER_UNDELETE` | `afterUndelete` | `newRecords()`, `newRecordsById()` |

Notice the arguments match what the platform makes available for each event:
insert events have no "old" data, delete events have no "new" data, and `before`
events have no Id map for new records (the records do not have Ids yet).

### 4. It flushes the buffer

`flushBuffers()` calls `RecordBuffer.flush()`, which merges everything staged
during the hook and performs the DML (one upsert per object type) before popping
the buffer context off the stack.

> **Why read context through methods instead of `Trigger.new` directly?**
> Every piece of context — `isExecuting()`, `operationType()`, `newRecords()`,
> and friends — is a `protected virtual` method, not a direct reference to the
> `Trigger` variables. That indirection is what lets tests **override** these
> methods to simulate a trigger without a real DML event. See
> [Testing Without a Trigger](#testing-without-a-trigger).

## Public API

`TriggerHandler` is a `public virtual inherited sharing` class. Almost its
entire surface is `protected` — designed to be **called or overridden by
subclasses**, not by outside callers.

> **A note on access modifiers:** in Apex, a member with **no access modifier is
> private**. The only such member here is `dispatch()`, which is therefore
> private and an implementation detail. Everything else is `protected` so
> subclasses can use it; `dispatch()` cannot be overridden.

> **A note on "properties":** `TriggerHandler` has **no public properties** and,
> in fact, no instance fields at all. It is pure behavior. All of its state
> comes from the trigger context it reads through the methods below.

### Lifecycle methods (call these from a subclass)

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `run` | `protected void run()` | `void` | The entry point. No-ops outside a trigger; otherwise stages buffers, dispatches to the matching hook, and flushes. A subclass must expose a public method that calls this — see [Wiring It Into a Trigger](#wiring-it-into-a-trigger). |
| `stageBuffers` | `protected void stageBuffers()` | `void` | Opens a `RecordBuffer` context via `RecordBuffer.start()`. Overridable if you need different setup. |
| `flushBuffers` | `protected void flushBuffers()` | `void` | Flushes the `RecordBuffer` via `RecordBuffer.flush()`. Overridable if you need different teardown. |

### Context accessors (override to mock; otherwise leave alone)

These are `protected virtual` and, in the base class, simply read the platform
`Trigger` variables (returning empty collections instead of `null`).

| Member | Signature | Returns | Base behavior |
| --- | --- | --- | --- |
| `isExecuting` | `protected virtual Boolean isExecuting()` | `Boolean` | `Trigger.isExecuting`. |
| `operationType` | `protected virtual System.TriggerOperation operationType()` | `System.TriggerOperation` | `Trigger.operationType`. |
| `newRecords` | `protected virtual List<SObject> newRecords()` | `List<SObject>` | `Trigger.new`, or an empty list if `null`. |
| `oldRecords` | `protected virtual List<SObject> oldRecords()` | `List<SObject>` | `Trigger.old`, or an empty list if `null`. |
| `newRecordsById` | `protected virtual Map<Id, SObject> newRecordsById()` | `Map<Id, SObject>` | `Trigger.newMap`, or an empty map if `null`. |
| `oldRecordsById` | `protected virtual Map<Id, SObject> oldRecordsById()` | `Map<Id, SObject>` | `Trigger.oldMap`, or an empty map if `null`. |

### Hook methods (override the ones you need)

All seven hooks are `protected virtual void` and **empty by default**. Override
only the events your object cares about; leave the rest alone and they do
nothing.

| Member | Signature |
| --- | --- |
| `beforeInsert` | `protected virtual void beforeInsert(List<SObject> records)` |
| `beforeUpdate` | `protected virtual void beforeUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById)` |
| `beforeDelete` | `protected virtual void beforeDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById)` |
| `afterInsert` | `protected virtual void afterInsert(List<SObject> records, Map<Id, SObject> recordsById)` |
| `afterUpdate` | `protected virtual void afterUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById, Map<Id, SObject> recordsById)` |
| `afterDelete` | `protected virtual void afterDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById)` |
| `afterUndelete` | `protected virtual void afterUndelete(List<SObject> records, Map<Id, SObject> recordsById)` |

### Private members

| Member | Signature | Description |
| --- | --- | --- |
| `dispatch` | `void dispatch()` | Private (no modifier). Reads `operationType()` and calls the matching hook with the matching arguments. Not overridable. |

## Wiring It Into a Trigger

Because `run()` is `protected`, an Apex trigger cannot call it directly — a
trigger lives outside the class and can only reach `public` members. The
intended pattern is:

1. **Subclass** `TriggerHandler` and override the hooks you need.
2. **Add one `public` method** to the subclass that calls `run()`.
3. **Have the trigger** instantiate the subclass and call that public method.

This keeps the trigger itself a one-liner — all logic lives in the testable
handler class. A complete, minimal example:

```apex
// 1 + 2 — the handler subclass
public class AccountTriggerHandler extends TriggerHandler {
    // Public entry point the trigger can reach. run() stays protected.
    public void execute() {
        this.run();
    }

    protected override void beforeInsert(List<SObject> records) {
        for (Account account : (List<Account>) records) {
            if (String.isBlank(account.ShippingCountry)) {
                account.ShippingCountry = 'USA';
            }
        }
    }
}
```

```apex
// 3 — the trigger: one line of real work
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new AccountTriggerHandler().execute();
}
```

The handler reads the context itself, so you list every event on the trigger and
let `dispatch()` decide which hook (if any) to run. Events you did not override
fall through to the empty base implementation and cost nothing.

> **Naming the public method is your choice.** The base class does not prescribe
> one. This page uses `execute()`; the unit tests use `runFromTest()`. Pick a
> convention and stick to it across your handlers.

## Examples

### Defaulting field values before insert

`before` hooks receive mutable records, so you change them in place — no DML
needed; the platform persists your edits when the `before` phase finishes.

```apex
public class LeadTriggerHandler extends TriggerHandler {
    public void execute() {
        this.run();
    }

    protected override void beforeInsert(List<SObject> records) {
        for (Lead lead : (List<Lead>) records) {
            if (lead.LeadSource == null) {
                lead.LeadSource = 'Web';
            }
        }
    }
}
```

### Reacting to a field change on update

`beforeUpdate` and `afterUpdate` hand you the old values keyed by Id, so you can
detect what actually changed instead of reacting to every save.

```apex
public class OpportunityTriggerHandler extends TriggerHandler {
    public void execute() {
        this.run();
    }

    protected override void afterUpdate(
        List<SObject> records,
        Map<Id, SObject> oldRecordsById,
        Map<Id, SObject> recordsById
    ) {
        for (Opportunity opp : (List<Opportunity>) records) {
            Opportunity previous = (Opportunity) oldRecordsById.get(opp.Id);
            Boolean justWon = opp.StageName == 'Closed Won'
                && previous.StageName != 'Closed Won';
            if (justWon) {
                // ... fire follow-up logic for newly won deals
            }
        }
    }
}
```

### Handling a delete

Delete hooks receive the records being removed (as `oldRecords`/`oldRecordsById`)
so you can run validation or cascade logic before the rows disappear.

```apex
public class AccountTriggerHandler extends TriggerHandler {
    public void execute() {
        this.run();
    }

    protected override void beforeDelete(
        List<SObject> oldRecords,
        Map<Id, SObject> oldRecordsById
    ) {
        for (Account account : (List<Account>) oldRecords) {
            if (account.Type == 'Strategic') {
                account.addError('Strategic accounts cannot be deleted.');
            }
        }
    }
}
```

### Overriding multiple hooks in one handler

A single handler can cover as many events as the object needs. Only the
overridden hooks do anything; the rest stay empty.

```apex
public class CaseTriggerHandler extends TriggerHandler {
    public void execute() {
        this.run();
    }

    protected override void beforeInsert(List<SObject> records) {
        // stamp defaults
    }

    protected override void beforeUpdate(
        List<SObject> records,
        Map<Id, SObject> oldRecordsById
    ) {
        // enforce state transitions
    }

    protected override void afterUndelete(
        List<SObject> records,
        Map<Id, SObject> recordsById
    ) {
        // re-index restored cases
    }
}
```

## Buffered DML

Every dispatch is wrapped in a `RecordBuffer`. Instead of calling `insert` or
`update` yourself inside a hook, you **stage** records with `RecordBuffer.put(...)`
and let `flushBuffers()` write them after the hook returns. This is how the
handler keeps your DML bulk-safe and centralized.

```apex
public class ContactTriggerHandler extends TriggerHandler {
    public void execute() {
        this.run();
    }

    protected override void afterInsert(
        List<SObject> records,
        Map<Id, SObject> recordsById
    ) {
        List<Task> followUps = new List<Task>();
        for (Contact contact : (List<Contact>) records) {
            followUps.add(new Task(
                WhoId = contact.Id,
                Subject = 'Welcome call'
            ));
        }
        // Staged now, upserted automatically when the buffer flushes.
        RecordBuffer.put(followUps);
    }
}
```

How `RecordBuffer` decides insert vs. update:

- Records **without** an `Id` are staged as inserts.
- Records **with** an `Id` are staged as updates.
- On flush, records are grouped by object type and written with one
  `DML.upsertRecords(...)` call per type.

> The buffer is opened and flushed **once per `run()`** — that is, once per
> trigger event. The unit tests exercise all seven operations in sequence and
> confirm exactly seven flushes occur, one per dispatched event.

## Testing Without a Trigger

The reason every context accessor is `protected virtual` is so a test can
subclass the handler and **feed it a fake trigger context** — no real DML
required. The library's own `TriggerHandlerTest` shows the pattern: a `Harness`
subclass overrides the accessors to return fields the test sets, and exposes a
public method that calls `run()`.

```apex
@IsTest
private class MyTriggerHandlerTest {
    // A test double that lets us inject context.
    private class Harness extends MyTriggerHandler {
        Boolean executing = false;
        System.TriggerOperation operation;
        List<SObject> records = new List<SObject>();
        Map<Id, SObject> oldById = new Map<Id, SObject>();

        public void runFromTest() {
            this.run();           // run() is protected, reachable from the subclass
        }

        void setContext(
            System.TriggerOperation op,
            List<SObject> newRecords,
            Map<Id, SObject> oldRecordsById
        ) {
            this.executing = true;
            this.operation = op;
            this.records = newRecords;
            this.oldById = oldRecordsById;
        }

        // Override the accessors so run() reads our fake context.
        protected override Boolean isExecuting() { return this.executing; }
        protected override System.TriggerOperation operationType() { return this.operation; }
        protected override List<SObject> newRecords() { return this.records; }
        protected override Map<Id, SObject> oldRecordsById() { return this.oldById; }
    }

    @IsTest
    static void defaultsCountryOnInsert() {
        // Build an in-memory record (see the TestData docs).
        Account account = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Acme')
            .build()[0];

        Harness harness = new Harness();
        harness.setContext(
            System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ account },
            null
        );

        harness.runFromTest();

        Assert.areEqual('USA', account.ShippingCountry, 'Expected beforeInsert to default the country.');
    }
}
```

To assert on **staged DML** without hitting the database, the library tests use
`DMLMock`: set the mock, run the handler, then read what was upserted.

```apex
DMLMock dmlMock = new DMLMock();
DML.setMock(dmlMock);

harness.runFromTest();

Assert.areEqual(1, dmlMock.upserts.size(), 'Expected the buffer to flush one upsert.');
```

> Verifying outside-trigger safety is easy: construct the handler, call its run
> method **without** setting any context, and assert nothing dispatched. With the
> base `isExecuting()` returning `false` outside a trigger (or your harness's
> flag still `false`), `run()` returns before any hook fires.

## Gotchas & Testing Notes

- **`run()` is protected — the trigger needs a public entry point.** A trigger
  cannot call `run()` directly. Add a `public` method (e.g. `execute()`) to your
  subclass that calls `this.run()`, and call that from the trigger.
- **No built-in recursion guard.** This class does not track re-entry. If your
  hook performs DML that re-fires the same trigger, you can recurse. If you need
  run-once-per-context behavior, add a `static Boolean` guard (or similar) in
  your subclass and check it inside the hook.
- **No metadata enable/disable switch.** There is no built-in way to bypass the
  handler from config. Anything like that is yours to add in the subclass.
- **Outside a trigger it does nothing.** `run()` returns immediately unless
  `isExecuting()` is `true`. This makes the handler safe to construct anywhere,
  but it also means you must override `isExecuting()` (or set its backing flag)
  in tests for `run()` to do anything.
- **Hook arguments mirror the platform.** `before insert` has no old data and no
  Id map for new records; delete events have no new records. Use the exact hook
  signature for the event — do not expect `oldRecordsById` in `beforeInsert`, for
  example.
- **Accessors never return `null`.** `newRecords()`, `oldRecords()`,
  `newRecordsById()`, and `oldRecordsById()` return empty collections rather than
  `null`, so you can iterate them without null checks.
- **Stage DML, do not call it.** Inside a hook, prefer `RecordBuffer.put(...)`
  over a raw `insert`/`update`. The handler flushes the buffer for you once per
  event, keeping DML bulk-safe and centralized.
- **`dispatch()` is private and final-ish.** It has no access modifier, so it is
  private and cannot be overridden. To change routing behavior you override the
  individual accessors or hooks, not `dispatch()`.
- **Test through a Harness subclass.** Override the `protected virtual` accessors
  to inject a fake context and expose a public method that calls `run()`. Combine
  with `TestData` for in-memory records and `DMLMock` for asserting flushed DML.
