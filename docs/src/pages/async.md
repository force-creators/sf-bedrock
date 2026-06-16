---
layout: ../layouts/DocsLayout.astro
title: Async | sf-bedrock docs
description: A tracked, configurable framework for record-driven Async Apex that drains high-volume work safely.
eyebrow: Frameworks
heading: Async
lede: Async turns record-driven background work into a tracked, configurable pipeline. You write one execute method, enqueue record Ids, and Bedrock drains the work in safe batches with visible success, retry, and error state.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Enqueueing Work
    href: "#enqueueing-work"
  - label: Staging Work
    href: "#staging-work"
  - label: Configuration
    href: "#configuration"
  - label: Multithreading
    href: "#multithreading"
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

`Async` is Bedrock's framework for background Apex that has to survive real
Salesforce volume. It is built for the work that should not run while a user
waits: recalculations, post-save enrichment, integration follow-up, compliance
checks, and other record-driven automation that can outgrow one transaction.

The public model is intentionally small:

- **Contract:** extend `Async` and override `execute(Set<Id> ids)`.
- **Start work:** call `Async.enqueue(...)` with records or Ids.
- **Coordinate work:** call `Async.stage(...)` from several services, then
  `Async.flush()` once.
- **Tune behavior:** use `Async_Job__mdt` and `Async_Settings__c` metadata for
  batch size, retry, priority, and per-user concurrency.

Use `Async` when you need background work that is tracked, retryable,
configurable, and able to drain record backlogs in tuned batches without
enqueueing one Queueable per record.

Use one async strategy consistently. Mixing ad hoc Queueables into trigger and
service code makes the org harder to reason about, especially when automation
runs inside automation. The painful failure is the trigger-side nightmare where
an async job performs DML, that DML calls a trigger, and the trigger tries to
enqueue another Queueable. In that async context the practical Queueable limit
is not 50; it is 1, so the second enqueue throws `Too many queueable jobs added
to the queue: 2`. Those failures are hard to diagnose because the enqueue can
be several layers away from the automation that created the async context.

`Async` packages those decisions into one contract: record intent, drain it in
managed batches, keep outcomes visible, and tune throughput in metadata. That
lets application code focus on business work instead of rediscovering Queueable
edge cases in every trigger path.

## Quickstart

Using `Async` as a subscriber is two steps.

Use `with sharing` or `inherited sharing` for subscriber classes unless the job
has a deliberate system-mode responsibility. `Async` coordinates background
work; your subscriber still owns its sharing, CRUD, and FLS boundary.

**Step 1** - extend `Async` and override `execute(Set<Id> ids)`. That method
receives one batch of record Ids. Query the current records, do the work, and use
Bedrock seams like `Query` and `DML` so the job stays testable.

```apex
public with sharing class RollupContactCountAsync extends Async {
    public override void execute(Set<Id> ids) {
        List<Account> accounts = (List<Account>) Query.records([
            SELECT Id, (SELECT Id FROM Contacts)
            FROM Account
            WHERE Id IN :ids
        ]);

        for (Account account : accounts) {
            account.Number_of_Contacts__c = account.Contacts.size();
        }

        DML.updateRecords(accounts);
    }
}
```

**Step 2** - call `Async.enqueue` with your class type and the records to
process.

```apex
List<Account> accounts = Query.records([
    SELECT Id
    FROM Account
    WHERE Industry = 'Technology'
]);

Async.enqueue(RollupContactCountAsync.class, accounts);
```

The caller records one work item per Account Id. Bedrock starts a managed
background chain when a concurrency slot is available, then calls your
`execute(Set<Id>)` method with safe batches until the queue is drained.

## Examples

### Refresh account health after high-volume changes

This example recalculates account health outside the user transaction. The
subscriber owns only the business behavior: query the current accounts, calculate
the field, and save the mutation.

```apex
public with sharing class RefreshAccountHealthAsync extends Async {
    public override void execute(Set<Id> ids) {
        List<Account> accounts = (List<Account>) Query.records([
            SELECT Id, AnnualRevenue, NumberOfEmployees, Health_Score__c
            FROM Account
            WHERE Id IN :ids
        ]);

        for (Account account : accounts) {
            account.Health_Score__c = calculateHealth(account);
        }

        DML.updateRecords(accounts);
    }

    static Decimal calculateHealth(Account account) {
        Decimal revenue = account.AnnualRevenue == null ? 0 : account.AnnualRevenue;
        Decimal employees = account.NumberOfEmployees == null ? 0 : account.NumberOfEmployees;
        return revenue > 1000000 && employees > 50 ? 100 : 50;
    }
}
```

Enqueue it from a service after deciding which records need recalculation:

```apex
List<Account> changedAccounts = Query.records([
    SELECT Id
    FROM Account
    WHERE LastModifiedDate = TODAY
]);

Async.enqueue(RefreshAccountHealthAsync.class, changedAccounts);
```

If the query returns 4,000 records, the caller records 4,000 work items in one
operation. Bedrock drains those records in configured batches, with each batch
running inside its own Queueable limits and each item ending in a visible success
or error state.

### Coordinate several services in one trigger flow

Use `stage` when independent services need to request background work in the same
transaction. Use `flush` once at the orchestration boundary.

```apex
public with sharing class ContactTriggerService {
    public void stageWelcomeEmails(List<Contact> contacts) {
        Async.stage(SendWelcomeEmailAsync.class, contacts);
    }

    public void stageComplianceReview(Set<Id> contactIds) {
        Async.stage(ReviewContactAsync.class, contactIds);
    }

    public void flushAsyncWork() {
        Async.flush();
    }
}
```

That keeps trigger-side services declarative: each service states the work it
needs, and the orchestrator decides when background work is created.

## Enqueueing Work

`enqueue` is the direct entry point for work that should be created immediately.
Pass either a `Set<Id>` or a list of records.

```apex
Set<Id> contactIds = new Set<Id>{ /* ... */ };
Async.enqueue(SendWelcomeEmailAsync.class, contactIds);

List<Contact> contacts = Query.records([
    SELECT Id
    FROM Contact
    WHERE MailingCountry = 'USA'
]);
Async.enqueue(SendWelcomeEmailAsync.class, contacts);
```

Both overloads create one work item per record Id. The `List<SObject>` overload
plucks Ids from the records; it does not keep the SObjects themselves.

`enqueue` does not run your `execute` method inline. It performs the work-item
insert operation, whose row count scales with the number of Ids, and the
framework may start one managed Queueable chain when a concurrency slot is
available. Processing happens later in background batches.

When `enqueue` is called from inside an `Async` job, Bedrock defers the new work
until the job finalizer runs. That lets a job touch setup objects and still add
follow-up work without mixing setup-object DML with work-item DML in the same
Queueable transaction.

### Why Ids, not SObjects

Background work runs in another transaction, at another time. A captured SObject
is only a snapshot of the record at enqueue time. By the time the job runs, a
user, flow, trigger, or integration may have changed the record.

`Async` keeps only Ids so each subscriber re-queries current data inside
`execute(Set<Id>)`. That is the safer default for automation that may run seconds
or minutes after the original transaction.

> If the payload itself is the work, use a purpose-built integration or event
> pattern. `Async` is for saved records that can be re-queried by Id.

## Staging Work

`stage` and `flush` are the transaction-level coordination API. They let several
services declare background work without scattering work-item inserts across the
transaction.

```apex
Async.stage(SendWelcomeEmailAsync.class, contacts);
Async.stage(ReviewContactAsync.class, contactIds);
Async.flush();
```

`stage` stores Ids in the current transaction buffer, grouped by subscriber
class. Duplicate Ids collapse naturally within each class. `flush` creates the
buffered work items in one controlled insert operation and clears the buffer.

This pattern is especially useful in trigger orchestration: domain services can
stage the work they own, while the trigger handler or service boundary flushes
once after all decisions have been made.

If `flush` runs inside an `Async` job, the staged work is moved into the job
finalizer instead of inserted directly in the Queueable transaction.

## Configuration

Async's control plane lives in metadata and settings. That means a team can tune
throughput, retry behavior, priority, and concurrency without changing the
subscriber class.

### Job metadata

By default, the framework processes **5 work items per batch**. Change that per
subscriber using `Async_Job__mdt`.

| Field | Meaning |
| --- | --- |
| `Apex__c` | Exact name of the `Async` subclass, e.g. `RefreshAccountHealthAsync`. |
| `Batch_Size__c` | How many work items one `execute` call receives. |
| `Max_Retries__c` | How many times the framework auto-retries a failed item before it stays in `Error`. Blank or `0` means auto-retry is off. |
| `Priority__c` | Assigned priorities run from lowest to highest within the same framework thread. Blank values mean no priority is assigned and sort last. |

For example, a record with `Apex__c = RefreshAccountHealthAsync` and
`Batch_Size__c = 50` makes each `execute` call receive up to 50 record Ids
instead of 5.

Priority is optional. Use lower numbers for work that should run sooner, and
higher numbers for work that can wait. Negative values are valid and run before
positive values. Leave `Priority__c` blank when a job should be unprioritized;
blank priorities drain after all assigned priorities in the same thread.

Choosing a batch size is a governor-limit trade-off:

- **Larger batches** do more per Queueable execution and finish in fewer jobs,
  but each batch must stay inside one Queueable's SOQL, DML, CPU, and callout
  limits.
- **Smaller batches** are safer per job and isolate failures to fewer records,
  but take more jobs to drain a large backlog.

Start at the default and raise the batch size only after measuring that the
subscriber comfortably fits inside one Queueable execution.

### Bounded auto-retry

Set `Max_Retries__c` when failures are likely to be transient, such as row locks
or short callout interruptions.

- Each work item tracks how many times the framework has re-run it.
- A failed item under the cap returns to `Pending` and is tried again.
- Once the retry count reaches `Max_Retries__c`, the item stays in `Error`.
- Blank or `0` means a failed item goes straight to `Error`.

Manual recovery still works separately: changing an errored work item back to
`Pending` is recognized by the framework and is not limited by
`Max_Retries__c`.

### Thread concurrency

`Thread_Settings__c.Max_Threads__c` controls how many framework-managed thread
chains may run at the same time. It is a hierarchical custom setting, so you can
keep the org default conservative and raise the cap for service users or other
high-volume identities.

Blank, `0`, and negative values default to **1**. A value of 1 keeps work
straight-line for that user. Higher values let separate enqueueing transactions
drain in parallel up to the configured soft cap.

## Multithreading

Async multithreading is backlog-based, not record-sharding-based. The important
unit is the enqueueing transaction.

One synchronous transaction creates one logical backlog. All work created in that
transaction stays linear inside that backlog: Bedrock pulls one configured batch,
calls `execute(Set<Id> ids)`, records the outcome, then chains to the next batch
until that backlog is empty.

Branching happens between backlogs. If several synchronous transactions create
work and `Thread_Settings__c.Max_Threads__c` allows more than one chain, those
backlogs can drain side by side. If the cap is `1`, one backlog drains while the
others wait.

![Diagram showing four synchronous transactions becoming four Async backlogs, three running in parallel under Max_Threads__c = 3 and one waiting for a slot.](/images/async-threading-model.png)

That model gives high-volume users more throughput without changing the
subscriber contract. The job still receives `Set<Id> ids`; configuration decides
how many framework-managed chains may run for the user.

There are two practical rules to remember:

- A single large `Async.enqueue(...)` call does not split itself across several
  parallel chains. It creates one backlog that drains batch by batch.
- Async and finalizer contexts stay conservative. When an async job performs DML
  and that DML fires triggers, the practical Queueable enqueue limit is 1, so
  Bedrock does not use those contexts to fan out extra chains.

> Branching is a throughput tool for independent synchronous transactions, not a
> way to make one subscriber process the same record set in parallel.

## Testing

The public testing path is to test the subscriber's job logic directly. Construct
the class and call `execute(Set<Id> ids)` with mock Ids. Mock the collaborators
your job uses, then assert the business mutation.

```apex
@istest
public with sharing class RefreshAccountHealthAsyncTest {
    @istest static void testExecute_updatesHealthScores() {
        List<Account> accounts = (List<Account>) new TestData(Account.sObjectType)
            .put(Account.Name, 'Test Account')
            .put(Account.AnnualRevenue, 2000000)
            .put(Account.NumberOfEmployees, 75)
            .mockIds()
            .count(3)
            .build();

        Query.setMock(new QueryMock(accounts));
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        new RefreshAccountHealthAsync().execute(Pluck.ids(accounts));

        Assert.areEqual(1, dmlMock.updates.size(), 'Expected one account update batch.');
        Assert.areEqual(3, dmlMock.updates[0].size(), 'Expected every queried account to be updated.');

        for (Account account : (List<Account>) dmlMock.updates[0]) {
            Assert.areEqual(
                100,
                account.Health_Score__c,
                'Expected high-value accounts to receive the high health score.'
            );
        }
    }
}
```

Use this pattern by default. It keeps subscriber tests fast, direct, and focused
on the behavior your class owns. The framework's queue orchestration is tested by
Bedrock.

## How It Works

Three ideas explain the parts you need as a user.

**One: records become tracked work.** `enqueue` stores one work item per record
Id. Each item records which subscriber should run, which record it represents,
and whether it is waiting, running, done, or in error.

**Two: managed chains drain work in batches.** Bedrock selects pending work for a
subscriber, marks that batch running, and calls your `execute(Set<Id> ids)`
method. The batch size comes from `Async_Job__mdt`, or the default of 5 when no
metadata record exists.

**Three: outcomes stay visible.** Successful items become `Done`. Failed items
become `Error` unless bounded auto-retry is configured and the item is still
under its retry cap. Follow-up work created inside an `Async` job is saved after
the job finishes, which keeps setup-object-sensitive transactions out of your
business code.

## Public API

> **A note on access modifiers.** In Apex, an omitted modifier means `private`.
> Members listed here are the intended subscriber-facing surface. Framework
> services, mocks, triggers, filters, and thread internals are not part of the
> public Async contract. Some framework-owned members are technically visible
> because Bedrock is source-first, but they are unsupported for app teams unless
> this page documents them as subscriber-facing.

### Job contract

| Member | Signature | Description |
| --- | --- | --- |
| `execute` | `public virtual void execute(Set<Id> ids)` | Override this in every subscriber. Receives the current batch of record Ids. The base implementation throws if a subclass does not override it. |

### Static entry points

| Member | Signature | Description |
| --- | --- | --- |
| `enqueue` | `public static void enqueue(Type jobType, List<SObject> records)` | Creates tracked work for each record Id plucked from the list. |
| `enqueue` | `public static void enqueue(Type jobType, Set<Id> recordIds)` | Creates tracked work for each Id. |
| `stage` | `public static void stage(Type jobType, List<SObject> records)` | Adds record Ids to the current transaction's async work buffer. |
| `stage` | `public static void stage(Type jobType, Set<Id> recordIds)` | Adds Ids to the current transaction's async work buffer. Duplicate Ids are merged by job type. |
| `flush` | `public static void flush()` | Creates all buffered work items in one operation, or defers them to the finalizer when called from inside an `Async` job. |

### Metadata and settings

| Artifact | Field | Purpose |
| --- | --- | --- |
| `Async_Job__mdt` | `Apex__c` | Exact API name of the `Async` subclass. |
| `Async_Job__mdt` | `Batch_Size__c` | Number of work items per `execute` call. Defaults to 5 when no record exists. |
| `Async_Job__mdt` | `Max_Retries__c` | Cap on framework auto-retries. Blank or `0` means auto-retry is off. |
| `Async_Job__mdt` | `Priority__c` | Assigned priorities run lowest to highest within the same backlog. Blank values leave work unprioritized and sort last. |
| `Thread_Settings__c` | `Max_Threads__c` | Maximum concurrent framework-managed thread chains. Blank or non-positive values default to 1. |

## Notes & Edge Cases

- **`enqueue` does not run your code inline.** It records work and returns. Your
  `execute` method runs later, in a background transaction.
- **`execute` receives a batch, not the full set.** Query once for the batch and
  write bulk-safe logic. Never put SOQL or DML inside a per-record loop.
- **Work from Ids, not captured records.** Even when you enqueue a
  `List<SObject>`, only Ids are kept. Re-query inside `execute` so you act on
  current data.
- **Override only `execute(Set<Id> ids)`.** The rest of the class is framework
  machinery.
- **Setup-object support applies inside Bedrock-managed async work.** When an
  `Async` job touches setup objects and then enqueues or flushes more work,
  Bedrock creates the child work after the job finishes. Outside the framework,
  `enqueue` creates work immediately in the caller's transaction.
- **Use `stage(...)` with `flush()` deliberately.** Staged work stays in the
  transaction buffer until `flush()` is called. If nothing flushes it, no work is
  created.
- **Tune batch size to the work.** Heavy jobs need smaller batches; light jobs
  can use larger batches to finish faster. Configure per class in
  `Async_Job__mdt`.
- **Tune concurrency with Thread settings.** `Max_Threads__c = 1` keeps one
  chain running. Higher values let separate enqueueing transactions drain in
  parallel.
- **Errors are recorded, not hidden.** A failing batch marks its work items
  `Error` with the exception message and stack trace saved for review.
- **Failed items can be retried two ways.** Configure bounded auto-retry with
  `Async_Job__mdt.Max_Retries__c`, or use the Console/operator recovery path
  where retry actions are available and permissions allow them. Manual recovery
  is an operational workflow, not a direct object-editing recipe.
- **There is no stuck-running recovery yet.** If a platform incident, aborted
  job, or finalizer failure leaves work stuck as running, recovery is a future
  hardening item.
