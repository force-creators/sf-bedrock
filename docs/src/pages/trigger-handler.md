---
layout: ../layouts/DocsLayout.astro
title: TriggerHandler | sf-bedrock docs
description: A lightweight base class that routes Apex trigger events to the right hook and wraps every dispatch in a RecordBuffer for automatic DML flushing.
eyebrow: Automation
heading: TriggerHandler
lede: A lightweight base class that reads the running trigger's context, routes it to the right before/after hook, and wraps the whole dispatch in a RecordBuffer so your handler can stage DML and have it flushed automatically.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Wiring Into a Trigger
    href: "#wiring-into-a-trigger"
  - label: Buffered DML
    href: "#buffered-dml"
  - label: Testing
    href: "#testing"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Notes & Edge Cases
    href: "#notes--edge-cases"
---

## Overview

`TriggerHandler` is the base class you subclass to handle Apex triggers in
sf-bedrock. It is a small implementation of the **Template Method pattern**. The
base class owns the fixed sequence — check context, open a buffer, route to a
hook, flush the buffer — and you fill in the parts specific to your object by
overriding the hooks you care about.

**Use `TriggerHandler` when** you want a thin, predictable place to put
trigger logic for an object, with the trigger context already unpacked and DML
staging handled for you.

**Reach for a plain Apex class instead when** your automation runs in a Flow,
batch job, or scheduled context — the handler does nothing outside an active
trigger and is designed only for that path.

> This is a deliberately minimal framework. It ships **no built-in recursion
> guard** and **no metadata-driven enable/disable switch**. If you need those,
> you add them in your subclass — the class is `virtual` precisely so you can.

## Quickstart

Subclass `TriggerHandler`, override the hook you need, and call `run()` from
your trigger:

```apex
// AccountTriggerHandler.cls
public class AccountTriggerHandler extends TriggerHandler {
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
// AccountTrigger.trigger
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new AccountTriggerHandler().run();
}
```

List every event on the trigger and let `dispatch()` decide which hook to call.
Events you did not override fall through to the empty base implementation and
cost nothing.

## Examples

### Defaulting field values before insert

`before` hooks receive mutable records, so you change them in place — no DML
needed; the platform persists your edits when the `before` phase finishes.

```apex
public class LeadTriggerHandler extends TriggerHandler {
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

`beforeUpdate` and `afterUpdate` hand you the old values keyed by Id, so you
can detect what actually changed instead of reacting to every save.

```apex
public class OpportunityTriggerHandler extends TriggerHandler {
    protected override void afterUpdate(
        List<SObject> records,
        Map<Id, SObject> oldMap
    ) {
        for (Opportunity opp : (List<Opportunity>) records) {
            Opportunity previous = (Opportunity) oldMap.get(opp.Id);
            Boolean justWon = opp.StageName == 'Closed Won'
                && previous.StageName != 'Closed Won';
            if (justWon) {
                // fire follow-up logic for newly won deals
            }
        }
    }
}
```

### Handling a delete

Delete hooks receive the records being removed so you can run validation or
cascade logic before the rows disappear.

```apex
public class AccountTriggerHandler extends TriggerHandler {
    protected override void beforeDelete(
        List<SObject> oldRecords,
        Map<Id, SObject> oldMap
    ) {
        for (Account account : (List<Account>) oldRecords) {
            if (account.Type == 'Strategic') {
                account.addError('Strategic accounts cannot be deleted.');
            }
        }
    }
}
```

### Covering multiple events in one handler

A single handler can cover as many events as the object needs. Only the
overridden hooks do anything; the rest stay empty.

```apex
public class CaseTriggerHandler extends TriggerHandler {
    protected override void beforeInsert(List<SObject> records) {
        // stamp defaults
    }

    protected override void beforeUpdate(
        List<SObject> records,
        Map<Id, SObject> oldMap
    ) {
        // enforce state transitions
    }

    protected override void afterUndelete(List<SObject> records) {
        // re-index restored cases
    }
}
```

## Wiring Into a Trigger

`run()` is `public`, so a trigger can call it directly on the subclass instance.
The intended pattern is:

1. **Subclass** `TriggerHandler` and override the hooks you need.
2. **Have the trigger** instantiate the subclass and call `run()`.

This keeps the trigger itself a one-liner — all logic lives in the testable
handler class:

```apex
trigger AccountTrigger on Account (
    before insert, before update, before delete,
    after insert, after update, after delete, after undelete
) {
    new AccountTriggerHandler().run();
}
```

If you prefer a named public entry point on the subclass (for example, to call
the handler from a test without going through the trigger), you can add one:

```apex
public class AccountTriggerHandler extends TriggerHandler {
    public void execute() {
        this.run();
    }
    // ... hook overrides
}
```

> **Naming the public wrapper is your choice.** The base class does not
> prescribe one. This page uses `execute()`; the library's own tests use
> `runFromTest()`. Pick a convention and stick to it across your handlers.

## Buffered DML

Every dispatch is wrapped in a `RecordBuffer`. Instead of calling `insert` or
`update` yourself inside a hook, **stage** records with `RecordBuffer.put(...)` and
let `flushBuffers()` write them after the hook returns. This keeps your DML
bulk-safe and centralized.

```apex
public class ContactTriggerHandler extends TriggerHandler {
    protected override void afterInsert(List<SObject> records) {
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

> The buffer is opened and flushed **once per `run()` call** — that is, once
> per trigger event. The library tests exercise all seven operations in sequence
> and confirm exactly seven flushes occur, one per dispatched event.

## Testing

Because every context accessor is `protected virtual`, a test can subclass the
handler and feed it a fake trigger context — no real DML required. The library's
own `TriggerHandlerTest` shows the pattern. A `Harness` subclass overrides the
accessors to return values the test controls, then calls `run()` (or a named
wrapper that calls `run()`) directly.

```apex
@istest
private class AccountTriggerHandlerTest {
    // A test double that injects a fake trigger context.
    private class Harness extends AccountTriggerHandler {
        Boolean executing = false;
        System.TriggerOperation operation;
        List<SObject> triggerNew = new List<SObject>();
        Map<Id, SObject> triggerOldMap = new Map<Id, SObject>();

        void setContext(
            System.TriggerOperation op,
            List<SObject> newRecords,
            Map<Id, SObject> oldRecordsById
        ) {
            this.executing = true;
            this.operation = op;
            this.triggerNew = newRecords == null ? new List<SObject>() : newRecords;
            this.triggerOldMap = oldRecordsById == null ? new Map<Id, SObject>() : oldRecordsById;
        }

        protected override Boolean isExecuting() { return this.executing; }
        protected override System.TriggerOperation operationType() { return this.operation; }
        protected override List<SObject> newRecords() { return this.triggerNew; }
        protected override Map<Id, SObject> oldRecordsById() { return this.triggerOldMap; }
    }

    @istest static void defaultsCountryOnInsert() {
        Account account = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Acme')
            .build()[0];

        Harness harness = new Harness();
        harness.setContext(
            System.TriggerOperation.BEFORE_INSERT,
            new List<SObject>{ account },
            null
        );

        harness.run();

        Assert.areEqual('USA', account.ShippingCountry, 'Expected beforeInsert to default the country.');
    }
}
```

To assert on **staged DML** without hitting the database, use `DMLMock`: set the
mock before calling `run()`, then read what was upserted.

```apex
DMLMock dmlMock = new DMLMock();
DML.setMock(dmlMock);

harness.run();

Assert.areEqual(1, dmlMock.upserts.size(), 'Expected the buffer to flush one upsert.');
```

> Verifying outside-trigger safety is easy. Construct the handler, call `run()`
> without setting any context on the harness (so `executing` stays `false`), and
> assert nothing dispatched. With `isExecuting()` returning `false`, `run()`
> returns before any hook fires.

## How It Works

Three ideas explain everything `TriggerHandler` does.

**1. The Template Method pattern.** `run()` owns the fixed sequence and
delegates the variable parts to virtual hook methods you override. You never
call the hooks yourself — you override them and let the framework call them at
the right moment. The base implementations are all empty, so anything you do not
override costs nothing.

**2. Virtual accessors as a test seam.** Every piece of trigger context —
`isExecuting()`, `operationType()`, `newRecords()`, `oldRecords()`,
`newRecordsById()`, `oldRecordsById()` — is a `protected virtual` method rather
than a direct reference to a `Trigger` variable. That indirection lets tests
subclass the handler, override those methods to return fake data, and call
`run()` without a real DML event. In production the base implementations simply
read the corresponding `Trigger.*` values.

**3. RecordBuffer wraps every dispatch.** Before calling the hook, `run()` calls
`RecordBuffer.start()` to open a buffer context. After the hook returns, it calls
`RecordBuffer.flush()` to write everything staged. Your hook never has to manage
DML timing — it stages records and the framework handles the rest.

The full sequence every time `run()` is called:

```
1. isExecuting() → false → return immediately (not in a trigger)
1. isExecuting() → true  → continue
2. stageBuffers()        → RecordBuffer.start()
3. dispatch()            → switch on operationType(), call one hook
4. flushBuffers()        → RecordBuffer.flush()
```

## Public API

`TriggerHandler` is a `public virtual inherited sharing` class. Almost its entire
surface is `protected` — designed to be called or overridden by subclasses, not
by outside callers. The one exception is `run()`, which must be reachable from a
trigger body.

> **A note on access modifiers:** in Apex, a member with **no access modifier is
> private**. The only such member here is `dispatch()`, which is therefore
> private and an implementation detail. Everything else is explicitly `protected`
> or `public`.

> **A note on "properties":** `TriggerHandler` has **no public properties** and,
> in fact, no instance fields at all. It is pure behavior. All state comes from
> the trigger context it reads through the methods below.

### Lifecycle methods

| Member | Signature | Description |
| --- | --- | --- |
| `run` | `public void run()` | The main entry point. Exits immediately unless `isExecuting()` is `true`; otherwise opens a buffer, dispatches to the matching hook, and flushes. |
| `stageBuffers` | `protected void stageBuffers()` | Opens a `RecordBuffer` context via `RecordBuffer.start()`. Overridable if you need different setup. |
| `flushBuffers` | `protected void flushBuffers()` | Flushes the `RecordBuffer` via `RecordBuffer.flush()`. Overridable if you need different teardown. |

### Context accessors (override to mock; otherwise leave alone)

These are `protected virtual` and, in the base class, simply read the platform
`Trigger` variables (returning empty collections instead of `null`).

| Member | Signature | Base behavior |
| --- | --- | --- |
| `isExecuting` | `protected virtual Boolean isExecuting()` | `Trigger.isExecuting` |
| `operationType` | `protected virtual System.TriggerOperation operationType()` | `Trigger.operationType` |
| `newRecords` | `protected virtual List<SObject> newRecords()` | `Trigger.new`, or an empty list if `null` |
| `oldRecords` | `protected virtual List<SObject> oldRecords()` | `Trigger.old`, or an empty list if `null` |
| `newRecordsById` | `protected virtual Map<Id, SObject> newRecordsById()` | `Trigger.newMap`, or an empty map if `null` |
| `oldRecordsById` | `protected virtual Map<Id, SObject> oldRecordsById()` | `Trigger.oldMap`, or an empty map if `null` |

### Hook methods (override the ones you need)

All seven hooks are `protected virtual void` and empty by default. Override
only the events your object cares about.

| Member | Signature |
| --- | --- |
| `beforeInsert` | `protected virtual void beforeInsert(List<SObject> records)` |
| `beforeUpdate` | `protected virtual void beforeUpdate(List<SObject> records, Map<Id, SObject> oldMap)` |
| `beforeDelete` | `protected virtual void beforeDelete(List<SObject> oldRecords, Map<Id, SObject> oldMap)` |
| `afterInsert` | `protected virtual void afterInsert(List<SObject> records)` |
| `afterUpdate` | `protected virtual void afterUpdate(List<SObject> records, Map<Id, SObject> oldMap)` |
| `afterDelete` | `protected virtual void afterDelete(List<SObject> oldRecords, Map<Id, SObject> oldMap)` |
| `afterUndelete` | `protected virtual void afterUndelete(List<SObject> records)` |

The arguments match what the platform makes available for each event: insert
events have no old data; delete events have no new records; `before` events have
no Id map for new records (records don't have Ids yet). If you need the
`newRecordsById` / `oldRecordsById` maps inside an `after` hook, call
`newRecordsById()` or `oldRecordsById()` directly.

### Private members

| Member | Signature | Description |
| --- | --- | --- |
| `dispatch` | `void dispatch()` | Private (no modifier). Reads `operationType()` and calls the matching hook with the matching arguments. Not overridable. |

## Notes & Edge Cases

- **`run()` is public** — a trigger can call it directly on the subclass
  instance. Adding a named wrapper (e.g. `execute()`) is a style choice, not a
  requirement.
- **No built-in recursion guard.** The class does not track re-entry. If your
  hook performs DML that re-fires the same trigger, you can recurse. Add a
  `static Boolean` guard in your subclass and check it at the top of the hook
  if you need run-once-per-context behavior.
- **No metadata enable/disable switch.** There is no built-in way to bypass the
  handler from configuration. Anything like that is yours to add in the subclass.
- **Outside a trigger it does nothing.** `run()` returns immediately unless
  `isExecuting()` is `true`. The handler is safe to construct anywhere, but you
  must override `isExecuting()` (or flip its backing flag) in tests for `run()`
  to do anything.
- **Hook arguments do not include both maps for after events.** `afterInsert`,
  `afterUpdate`, and `afterUndelete` receive the new records list and, for update,
  the `oldMap` — but not a `newRecordsById` argument. If you need a map of new
  records inside those hooks, call `this.newRecordsById()` directly.
- **Accessors never return `null`.** `newRecords()`, `oldRecords()`,
  `newRecordsById()`, and `oldRecordsById()` return empty collections rather than
  `null`, so you can iterate them safely.
- **Stage DML, do not call it.** Inside a hook, prefer `RecordBuffer.put(...)`
  over a raw `insert` or `update`. The handler flushes the buffer once per
  event, keeping DML bulk-safe and centralized.
- **`dispatch()` is private and final.** It has no access modifier, so it is
  private and cannot be overridden. To change routing behavior, override
  individual accessors or hooks — not `dispatch()`.
- **Test through a Harness subclass.** Override the `protected virtual` accessors
  to inject a fake context, then call `run()` directly. Combine with `TestData`
  for in-memory records and `DMLMock` to assert on flushed DML.
