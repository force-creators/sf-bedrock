---
layout: ../layouts/DocsLayout.astro
title: Async | sf-bedrock docs
description: A base class for running setup-object-safe Apex work in the background that scales to thousands of records without tripping over Salesforce's Queueable limits.
eyebrow: Async Services
heading: Async
lede: A base class for running setup-object-safe Apex work in the background that scales to thousands of records without tripping over Salesforce's Queueable limits. You write one method; the framework persists the work, drains it in safe batches, and tracks every job to success or error.
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

Some work is too slow or too heavy to do while a user waits — recalculating
every contact on an account, calling an external API for a few thousand records,
rolling up data across a large object. The Salesforce answer is *asynchronous*
Apex, and the most flexible flavor is the **Queueable**.

But raw Queueables are easy to get wrong at volume. The platform enforces hard
limits that a junior developer usually discovers the hard way:

- You can only **enqueue 50 jobs** in a single transaction.
- A running Queueable can **chain only one** child Queueable.
- Each Queueable execution has its **own governor limits** (SOQL rows, CPU, DML),
  so you cannot just "process everything" in one job.

The naive approach — loop over records and enqueue one Queueable each — blows the
50-job limit the moment you have more than 50 records, and gives you no record of
what ran, what failed, or what is left to do.

`Async` solves this. Instead of enqueuing a Queueable per record, you hand the
framework a set of record Ids. It **saves them as work items** in a custom object,
then runs a single managed background thread that drains those work items a
**safe batch at a time**, chaining one job to the next until the queue is empty.
Every work item is tracked through `Pending → Running → Done` (or `Error`), so
nothing is silently lost.

Because framework-managed follow-up work is created from the Queueable
finalizer, an `Async` job can touch setup objects and still call `Async.enqueue`
or `Async.stage` for more work. That keeps mixed-DML-sensitive framework writes
out of the subscriber's Queueable transaction.

## Quickstart

Using `Async` as a subscriber is two steps.

**Step 1** — extend `Async` and override `execute(Set<Id> ids)`. That method is
the only code you write. It receives a batch of record Ids and does the work for
that batch. Here it counts the Contacts on each Account and stores the total on
the parent — the kind of roll-up a native summary field cannot do across a
lookup relationship.

```apex
public with sharing class RollupContactCountAsync extends Async {

    public override void execute(Set<Id> ids) {
        List<Account> accounts = Query.records([
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

**Step 2** — call `Async.enqueue` with your class type and the records to
process. Do this from anywhere: a trigger handler, a service method, a
controller.

```apex
List<Account> accounts = Query.records([
    SELECT Id FROM Account WHERE Industry = 'Technology'
]);
Async.enqueue(RollupContactCountAsync.class, accounts);
```

That is everything. The framework creates one work item per Account Id, starts a
background thread, and drains the queue in batches — each calling your
`execute` method with a small slice of Ids until every Account is recounted.

## Examples

### Background-update a field on many records

```apex
public with sharing class FlagStaleContactsAsync extends Async {
    public override void execute(Set<Id> ids) {
        List<Contact> contacts = Query.records([
            SELECT Id, Description FROM Contact WHERE Id IN :ids
        ]);
        for (Contact contact : contacts) {
            contact.Description = 'Reviewed by background job';
        }
        DML.updateRecords(contacts);
    }
}
```

Enqueue it from a trigger handler or service:

```apex
List<Contact> stale = Query.records([
    SELECT Id FROM Contact WHERE LastActivityDate < LAST_N_DAYS:90
]);
Async.enqueue(FlagStaleContactsAsync.class, stale);
```

If `stale` returns 4,000 records, the calling transaction records 4,000 work
items. With the default batch size the framework runs 800 background batches of
5, one chaining to the next, each within its own limits.

## Enqueueing Work

```apex
// From a Set<Id> you already have:
Set<Id> contactIds = new Set<Id>{ /* ... */ };
Async.enqueue(SendWelcomeEmailAsync.class, contactIds);

// Or directly from a list of records — the framework plucks their Ids for you:
List<Contact> contacts = Query.records([
    SELECT Id FROM Contact WHERE MailingCountry = 'USA'
]);
Async.enqueue(SendWelcomeEmailAsync.class, contacts);
```

Both overloads do the same thing: they create one **work item** per record Id
and mark it `Pending`. That is all `enqueue` does in the calling transaction. It
does **not** run your `execute` method inline. Processing happens afterward, in
the background, on the framework's managed thread.

When `enqueue` is called from inside an `Async` job, the framework defers the
new work until the job's finalizer runs. That means a job can update setup
objects, such as groups or users, and still enqueue follow-up work without
mixing setup-object DML with `Async__c` work-item DML in the same Queueable
transaction.

This is the scaling win: whether you enqueue 5 records or 5,000, the calling
transaction does the same small amount of work (insert the work items). You never
approach the 50-job limit, because you are not enqueuing one job per record —
you are recording intent, and a single thread drains it.

### Why Ids, not SObjects

Even the `List<SObject>` overload throws the records away and keeps only their
Ids. That is not a limitation; it is the design protecting you from a classic,
hard-to-debug async bug.

**Background work runs in a different transaction, at a different time.** When
you call `enqueue`, the job does not run then and there. It might run a fraction
of a second later, or — if the queue is busy, limits are tight, or a job had to
retry — minutes later. An `SObject` captured at enqueue time is a frozen snapshot
of that record as it looked in that moment. By the time the job actually runs, the
real record may have changed: a user edited a field, another automation updated
the status, or the record was modified several more times.

**Forcing Ids removes the trap entirely.** An Id is permanent and never goes
stale. Because all you carry into the job is an identifier, the only way to act
on the record is to re-query it inside `execute`. That means you are always
working with the *current* state of the data at the moment the work runs.

> **What if I genuinely need to carry data, not just Ids?** Sometimes the work
> *is* the payload — a blob of values with no saved record to re-query, or data
> you specifically want to act on as it was at publish time. That is a different
> shape of problem with a different tool: the **Event** framework, which is built
> for stateless, self-contained payloads passed into async processing. Reach for
> `Async` when you are processing **records** (pass Ids); reach for `Event` when
> you are processing **data** (pass the payload). Don't try to smuggle stateful
> records through `Async`.

## Staging Work

Use `stage` and `flush` when several services in the same transaction may add
work and you want one work-item insert at the controlled flush point. This is a
natural fit for trigger orchestration: each domain service can stage the records
it cares about, and the trigger handler can flush once.

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

`flush` merges duplicate Ids by async class, creates all staged work items in a
single DML call, and then clears the buffer. If `flush` runs inside an `Async`
job, the staged work is moved into the job finalizer instead of inserted in the
Queueable transaction.

## Configuration

By default the framework processes **5 work items per batch**. You can change
that per Apex class — without touching code — using the `Async_Config__mdt`
custom metadata type. Create a record with:

| Field | Meaning |
| --- | --- |
| `Apex__c` | The exact name of your `Async` subclass, e.g. `FlagStaleContactsAsync`. |
| `Batch_Size__c` | How many work items one batch (one `execute` call) processes. |
| `Max_Retries__c` | How many times the framework auto-retries a failed item before it rests in `Error`. Absent or `0` ⇒ auto-retry off. |

For example, a record with `Apex__c = FlagStaleContactsAsync` and
`Batch_Size__c = 50` makes each `execute` call receive up to 50 record Ids
instead of 5.

**Choosing a batch size is a governor-limit trade-off:**

- **Larger batches** do more per Queueable execution — fewer total jobs, faster
  overall — but each `execute` must finish within one Queueable's limits (SOQL
  rows, DML rows, CPU time). If your `execute` is heavy (callouts, lots of DML,
  complex CPU work), keep the batch small.
- **Smaller batches** are safer per job and isolate failures to fewer records,
  but take more total jobs to drain a large queue.

Start at the default and raise the batch size only when you have measured that a
batch comfortably fits inside one Queueable's limits.

> If no `Async_Config__mdt` record exists for your class, the framework falls
> back to a batch size of **5**. You only need a metadata record when you want
> something other than the default.

### Bounded auto-retry

When a batch fails, the framework can retry it for you instead of leaving every
item in `Error`. Set `Max_Retries__c` on the job type's `Async_Config__mdt`
record to turn it on:

- Each `Async__c` work item carries a `Retry_Count__c` (starts at `0`) that
  tracks how many times the framework has re-run it.
- On failure, an item whose `Retry_Count__c` is **under** `Max_Retries__c` is
  re-queued to `Pending` with its counter incremented, and the chain runs it
  again.
- Once `Retry_Count__c` reaches `Max_Retries__c`, the item rests in terminal
  `Error`. A job with `Max_Retries__c = 3` therefore runs once, retries up to
  three more times, then stops.
- With `Max_Retries__c` absent or `0`, a failed item goes straight to `Error` —
  no auto-retry.

Auto-retry is for transient failures that self-heal (a row lock, a brief callout
hiccup). It does not change manual recovery: flipping an `Error` item back to
`Pending` yourself is still unbounded, always honored, and never touches
`Retry_Count__c`.

## Testing

The primary way to unit test an `Async` subscriber is to test only the job
logic: construct the class and call `execute(Set<Id> ids)` directly. This keeps
separation of concerns clear. You are testing your job's behavior, not thread
drain logic, work item lifecycle, or framework wiring.

### Testing Async Jobs

```apex
@istest
public with sharing class FlagStaleContactsAsyncTest {

  @istest static void testExecute_updatesDescriptions_directly() {
    List<Contact> contacts = (List<Contact>) new TestData(Contact.sObjectType)
        .put(Contact.LastName, 'Test')
        .mockIds()
        .count(3)
        .build();
    DML.insertRecords(contacts);

    Set<Id> ids = Pluck.ids(contacts);

    new FlagStaleContactsAsync().execute(ids);

    for (Contact contact : (List<Contact>) Query.records([
        SELECT Description FROM Contact WHERE Id IN :ids
    ])) {
      Assert.areEqual('Reviewed by background job', contact.Description,
        'Expected direct execute() to update each contact description.');
    }
  }
}
```

Use this pattern by default. It is faster, easier to read, and avoids coupling
your unit test to framework internals.

### Testing Chains of Work

When you specifically want to verify framework-level behavior (work item
creation, status transitions, and queue chaining), use this pattern:

```apex
@istest
public with sharing class FlagStaleContactsAsyncTest {

    @istest
    static void testFlagsContacts_inBackground() {
        List<Contact> contacts = (List<Contact>) new TestData(Contact.sObjectType)
            .put(Contact.LastName, 'Test')
            .mockIds()
            .count(3)
            .build();
        DML.insertRecords(contacts);

        // canEnqueue() lets the async chain actually run during the test.
        AsyncMock mock = new AsyncMock().canEnqueue();
        Async.setMock(mock);

        Test.startTest();
            Async.enqueue(FlagStaleContactsAsync.class, contacts);
        Test.stopTest();

        // Every work item should have completed.
        for (Async__c workItem : (List<Async__c>) Query.records([
            SELECT Status__c FROM Async__c
        ])) {
            Assert.areEqual('Done', workItem.Status__c,
                'Expected every async work item to finish as Done.');
        }

        // And the job's side effect should have happened.
        for (Contact contact : (List<Contact>) Query.records([
            SELECT Description FROM Contact
        ])) {
            Assert.areEqual('Reviewed by background job', contact.Description,
                'Expected the async job to update each contact description.');
        }
    }
}
```

What each piece does:

- **`new AsyncMock().canEnqueue()`** turns on enqueuing inside a test. By default
  the framework refuses to start its thread while a test is running (so you don't
  accidentally fire real background work). `canEnqueue()` opts this test in so the
  chain runs and drains during `Test.stopTest()`. The mock caps Queueable stack
  depth at 5 in tests, which practically means up to 4 unique async jobs can be
  chained through this pattern in a single unit test.
- **`Async.setMock(mock)`** installs the mock services for the current
  transaction.
- **Enqueue inside `Test.startTest()`** and let `Test.stopTest()` flush the
  asynchronous work. Then assert on two things: the **work item statuses** (proof
  the framework ran your job to completion) and the **side effect** of your
  `execute` (proof your logic did the right thing).

Use this second pattern intentionally, not as your default. It is more of an
integration test for the framework chain plus your subscriber.

You can also define the subscriber class as a small inner class in the test when
you only need it there, exactly as `AsyncTest` does with its `MyTestAsync` inner
class.

## How It Works

Three ideas explain everything `Async` does.

**One: work items replace Queueables as the unit of scale.** When you call
`enqueue`, the framework does not enqueue one Queueable per record. It inserts one
`Async__c` row per record Id (`Status__c = 'Pending'`), tagged with the target
Apex class name and a **thread Id** (the current request Id) that groups
everything enqueued in the same transaction. A trigger on `Async__c` then starts
exactly one background Queueable — the thread — for that group. The calling
transaction touches a bounded number of limits regardless of how many records you
enqueue.

**Two: a thread drains the queue one batch at a time.** `AsyncThread` is a
Queueable that holds a thread Id. When it runs, it hands off to
`JobService.enqueueNextJob()`, which selects the next `Pending` work item for
that thread (FIFO, with `Priority__c DESC` applied first) and reads `Async_Config__mdt`
for the batch size (defaulting to 5). It gathers up to that many matching
same-Apex work items, marks them `Running`, dynamically instantiates your
class by name, calls `setWork(threadId, workItemIds)` on it, and enqueues it as a
Queueable.

**Three: a `Finalizer` closes the loop.** `Async.JobWatcher` is attached before
your `execute` runs. On success it marks the batch `Done`, creates any child work
that was enqueued or flushed from inside the job, and chains the next batch by
calling `enqueueNextJob()` again. On failure it hands the batch to
`JobService.handleFailure`, which checks each item against its job type's
`Max_Retries__c`: items still under the cap are re-queued to `Pending` with
`Retry_Count__c` incremented (so the chain re-runs them), and items at the cap —
or any item when auto-retry is off — are marked `Error` with the truncated
message and stack trace saved on the `Async__c` rows. Either way it then chains
the remaining work. Failures are recorded, not silent, and they do not stop the
rest of the queue.

That finalizer handoff is what makes framework-managed child work safe after
setup-object DML. Your subscriber can touch setup objects in `execute`, then call
`Async.enqueue` or `Async.flush`; Bedrock writes the new `Async__c` work items
from the finalizer transaction.

The retry path closes the loop from the other direction: `AsyncTriggerHandler`
watches for `Async__c` updates where `Status__c` flips from `Error` back to
`Pending` (via `AsyncFilters.shouldRetry`). When that happens, a new thread
starts for those items. This is how external tooling or manual intervention can
re-drive failed work.

## Public API

> **A note on access modifiers.** In Apex, an omitted modifier means `private`.
> Members listed here without an access modifier are private to the class and
> not accessible from outside it. `@testVisible` members are private in
> production but accessible in test classes.

### Static members (`Async`)

| Member | Signature | Description |
| --- | --- | --- |
| `jobs` | `public static JobService` | Service singleton for thread start and job dispatch. Swap via `setMock`. |
| `work` | `public static WorkService` | Service singleton for `Async__c` status transitions. Swap via `setMock`. |
| `queries` | `public static QueryService` | Service singleton for `Async__c` reads. Swap via `setMock`. |
| `metadata` | `public static MetadataService` | Service singleton for cached `Async_Config__mdt` reads, keyed by Apex name. Swap via `setMock`. |
| `setMock` | `@testVisible static void setMock(AsyncMock mock)` | Replaces all four service singletons with the mock's equivalents. Test-visible only. |
| `enqueue` | `public static void enqueue(Type jobType, List<SObject> records)` | Creates one `Async__c` work item per record Id (Ids are plucked from the list). |
| `enqueue` | `public static void enqueue(Type jobType, Set<Id> recordIds)` | Creates one `Async__c` work item per Id in `recordIds`. |
| `stage` | `public static void stage(Type jobType, List<SObject> records)` | Adds record Ids to the current transaction's async work buffer. Ids are plucked from the list. |
| `stage` | `public static void stage(Type jobType, Set<Id> recordIds)` | Adds record Ids to the current transaction's async work buffer. Duplicate Ids are merged by job type. |
| `flush` | `public static void flush()` | Creates all buffered work items in one DML call, or defers them to the finalizer when called from inside an `Async` job. |

### Instance members (`Async`)

| Member | Signature | Description |
| --- | --- | --- |
| `execute` | `public virtual void execute(Set<Id> ids)` | The subscriber override hook. The base implementation throws `AsyncException`; every subclass must override this. Receives the current batch's record Ids, freshly re-queried from `Async__c`. |

### `Async.AsyncException`

`public class AsyncException extends Exception` — thrown when `execute(Set<Id>)`
is called on the base class without being overridden.

### `AsyncMock`

| Member | Signature | Description |
| --- | --- | --- |
| `canEnqueue` | `public AsyncMock canEnqueue()` | Enables thread enqueuing inside a test. Returns `this` for fluent chaining. By default `AsyncMock.JobService.canEnqueue()` returns `false` and no thread starts. |
| `config` | `public AsyncMock config(Type jobType, Async_Config__mdt config)` | Injects config for a job type into the `MetadataService` cache without DML. Returns `this` for fluent chaining. |
| `work` | `public WorkService work` | Mock `WorkService` (extends `Async.WorkService`). |
| `jobs` | `public JobService jobs` | Mock `JobService` (extends `Async.JobService`). Caps `maximumQueueableStackDepth` at 5. |
| `queries` | `public QueryService queries` | Mock `QueryService` (extends `Async.QueryService`). |
| `metadata` | `public MetadataService metadata` | Mock `MetadataService` (extends `Async.MetadataService`). Serves injected config before falling back to a real read. |

### Schema

The framework relies on two metadata types in
`force-app/bedrock/lib/async/objects`.

**`Async__c`** (custom object) — one row per work item:

| Field | Purpose |
| --- | --- |
| `Apex__c` | API name of the `Async` subclass to run. |
| `Record_Id__c` | The Id of the record this work item represents. |
| `Status__c` | Lifecycle status: `Pending`, `Running`, `Done`, `Error`. |
| `Thread__c` | Request Id that groups work items enqueued in the same transaction. |
| `Priority__c` | Higher values are processed first within a thread. |
| `Retry_Count__c` | Number of times the framework has re-run this item. Starts at `0`; incremented on each auto-retry. |
| `Error_Message__c` | Truncated exception message on failure (max 32,768 chars). |
| `Error_Stack_Trace__c` | Truncated stack trace on failure (max 32,768 chars). |

**`Async_Config__mdt`** (custom metadata type) — one record per subclass that
needs a non-default batch size or auto-retry:

| Field | Purpose |
| --- | --- |
| `Apex__c` | API name of the `Async` subclass. |
| `Batch_Size__c` | Number of work items per `execute` call. Defaults to 5 when no record exists. |
| `Max_Retries__c` | Cap on framework auto-retries for failed items. Absent or `0` ⇒ auto-retry off. |

## Notes & Edge Cases

- **`enqueue` does not run your code inline.** It records work items and returns.
  Your `execute` runs later, in the background. Do not assert on its side effects
  in the same synchronous block — in a test, assert after `Test.stopTest()`.
- **`execute` receives a batch, not the full set.** Write it to handle whatever
  `ids` it is given, bulk-safely. Query once for the batch; never SOQL or DML
  inside a per-record loop.
- **Work from Ids, not captured records.** Even when you enqueue a
  `List<SObject>`, only the Ids are kept. Re-query inside `execute` so you act on
  current data, not a stale snapshot.
- **Override only `execute(Set<Id> ids)`.** The rest of the class is framework
  machinery. As a subscriber you should not need to touch it.
- **Setup-object support applies inside Bedrock-managed async work.** When an
  `Async` job touches setup objects and then enqueues or flushes more work,
  Bedrock creates the child `Async__c` rows from the finalizer. Outside the
  framework, `enqueue` still creates work immediately in the caller's
  transaction.
- **Use `stage(...)` with `flush()` deliberately.** Staged work stays in the
  transaction buffer until `flush()` is called. If nothing flushes it, no work
  items are created.
- **Tune batch size to the work.** Heavy jobs (callouts, large DML, CPU-intensive
  processing) need smaller batches to stay inside one Queueable's governor limits;
  light jobs can use larger batches to finish faster. Configure per class in
  `Async_Config__mdt`; the default is 5.
- **Errors are recorded, not hidden.** A failing batch marks its work items
  `Error` with the message and stack trace saved on the `Async__c` record. Check
  there when a background job does not produce the expected results.
- **Failed items can be retried two ways.** The framework auto-retries failures
  up to `Async_Config__mdt.Max_Retries__c` (off by default), incrementing
  `Retry_Count__c` each time. Separately, flipping a failed `Async__c` row back to
  `Pending` (with the correct `Thread__c`) triggers `AsyncTriggerHandler` to start
  a new thread via `AsyncFilters.shouldRetry`. Manual flips are unbounded — they
  work even past `Max_Retries__c` — and never change `Retry_Count__c`.
- **`canEnqueue()` must be called to run the chain in tests.** Without
  `new AsyncMock().canEnqueue()`, `JobService.canEnqueue()` returns `false` and no
  thread starts — `enqueue` inserts work items but nothing processes them.
