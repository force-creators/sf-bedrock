---
layout: ../layouts/DocsLayout.astro
title: Async | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock Async framework for scalable Queueable Apex.
eyebrow: Async Services
heading: Async
lede: A base class for running Apex work in the background that scales to thousands of records without tripping over Salesforce's Queueable limits. You write one method; the framework persists the work, drains it in safe batches, and tracks every job to success or error.
sections:
  - label: Why Async
    href: "#why-async"
  - label: The Two-Step Contract
    href: "#the-two-step-contract"
  - label: Enqueueing Work
    href: "#enqueueing-work"
  - label: How It Works
    href: "#how-it-works"
  - label: Configuration
    href: "#configuration"
  - label: Examples
    href: "#examples"
  - label: Testing
    href: "#testing"
  - label: Gotchas & Notes
    href: "#gotchas-and-notes"
---

## Why Async

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

The naive approach — "loop over my records and enqueue one Queueable each" —
blows the 50-job limit the moment you have more than 50 records, and gives you
no record of what ran, what failed, or what is left to do.

`Async` solves this for you. Instead of enqueuing a Queueable per record, you
hand the framework a set of record Ids. It **saves them as work items** in a
custom object, then runs a single managed background "thread" that drains those
work items a **safe batch at a time**, chaining one job to the next until the
queue is empty. Every work item is tracked through `Pending → Running → Done`
(or `Error`), so nothing is silently lost.

> **Use `Async` when** you have a body of record work that should happen in the
> background and might involve more records than you can safely process in one
> synchronous transaction. You describe *what to do to a batch of records*; the
> framework decides *how many to run at once and when*.

## The Two-Step Contract

Using `Async` as a subscriber is two steps. There is nothing else to wire up.

### 1. Extend `Async`

Create a class that **extends `Async`** and **overrides `execute(Set<Id> ids)`**.
That method is the only code you own — it receives a batch of record Ids and does
the work for that batch.

```apex
public with sharing class HelloWorldAsync extends Async {

    public override void execute(Set<Id> ids) {
        List<Contact> contacts = [SELECT Id, LastName FROM Contact WHERE Id IN :ids];
        for (Contact contact : contacts) {
            // ... do your background work for this batch of records
        }
    }

}
```

Two things to notice, because they are the whole point of the pattern:

- **You receive Ids, not records.** The framework persists *Ids* and re-queries
  the records fresh inside `execute`. Background work can run seconds or minutes
  after it was requested, by which time the original records may have changed —
  so you always work from current data, not a stale snapshot.
- **`ids` is a single batch, not everything you enqueued.** If you enqueue 500
  records, `execute` is called many times, each with a small slice (5 by
  default). Your method must be **bulk-safe over the batch it receives** — query
  once for the whole `ids` set and operate on the list, exactly as above. Never
  put a SOQL query or DML statement inside a per-record loop.

### 2. Override `execute`, not anything else

`Async` exposes a lot of public surface (services for jobs, work, and queries),
but **as a subscriber the only member you override is `execute(Set<Id> ids)`**.
Everything else — enqueuing the thread, batching, status tracking, chaining,
finalizers — is the framework's job. If you find yourself overriding other
methods, you have left subscriber territory and should talk to the framework
owner.

## Enqueueing Work

To run your class in the background, call `Async.enqueue` with your class type
and the records (or record Ids) to process:

```apex
// From a Set<Id> you already have:
Set<Id> contactIds = new Set<Id>{ /* ... */ };
Async.enqueue(HelloWorldAsync.class, contactIds);
```

```apex
// Or directly from a list of records — the framework plucks their Ids for you:
List<Contact> contacts = [SELECT Id FROM Contact WHERE MailingCountry = 'USA'];
Async.enqueue(HelloWorldAsync.class, contacts);
```

Both overloads do the same thing: they create one **work item** per record Id
and mark it `Pending`. That is all `enqueue` does in the calling transaction —
it does **not** run your `execute` method inline. The actual processing happens
afterward, in the background, on the framework's managed thread.

> **Pass Ids, never stateful records.** Even the `List<SObject>` overload only
> keeps the Ids. This is deliberate: an `SObject` captured now can be out of date
> by the time the job runs. Hand the framework identifiers and let `execute`
> re-query — that is the safe, scalable contract.

This is the scaling win in one line: whether you enqueue 5 records or 5,000, the
calling transaction does the same small amount of work (insert the work items).
You never approach the 50-job limit, because you are not enqueuing one job per
record — you are recording intent, and a single thread drains it.

### Why Ids, not SObjects

This is the single most important idea in the framework, so it is worth slowing
down on. `Async` deliberately makes you work with **record Ids** — even the
`List<SObject>` overload throws the records away and keeps only their Ids. That
is not a limitation to work around; it is the design protecting you from a
classic, hard-to-debug async bug.

**Background work runs in a different transaction, at a different time.** When
you call `enqueue`, the job does not run then and there. It might run a fraction
of a second later, or — if the queue is busy, limits are tight, or a job had to
retry — minutes later. **An `SObject` you captured at enqueue time is a frozen
snapshot of that record as it looked in that moment.** By the time the job
actually runs, the real record may have moved on:

- Another user (or another automation) edited a field.
- A different process changed the record's status, owner, or amount.
- The record was updated several more times after you enqueued it.

If the framework let you pass that frozen `SObject` into your job, your code
would happily operate on **stale data** — overwriting newer values, making
decisions on a field that has since changed, or "winning" a race it should have
lost. These bugs are nasty precisely because they are intermittent: everything
works in a quiet sandbox and only breaks under real concurrent load.

**Forcing Ids removes the trap entirely.** An Id is permanent and never goes
stale. Because all you carry into the job is an identifier, the only way to act
on the record is to **re-query it inside `execute`** — which means you are always
looking at the *current* state of the data at the moment the work actually runs:

```apex
public override void execute(Set<Id> ids) {
    // Fresh read, in the job's own transaction — never a stale snapshot.
    List<Contact> contacts = [SELECT Id, Email, Status__c FROM Contact WHERE Id IN :ids];
    // ... now your decisions are based on current data
}
```

So the rule "pass Ids, re-query in `execute`" is not ceremony — it is the
framework steering every subscriber onto the only safe path by default.

> **What if I genuinely need to carry data, not just Ids?** Sometimes the work
> *is* the payload — you have a blob of values to process that doesn't
> correspond to a saved record you can re-query, or you specifically want to act
> on the data as it was at publish time. That is a different shape of problem,
> and it has a different tool: the **Event** framework, which is built for
> stateless, self-contained payloads passed through to async processing. Reach
> for `Async` when you are processing **records** (pass Ids); reach for `Event`
> when you are processing **data** (pass the payload). Don't try to smuggle
> stateful records through `Async` — use the framework designed for it.

## How It Works

You do not need to operate the machinery below, but understanding it helps you
reason about timing, batch size, and errors.

1. **`enqueue` saves work items.** Each record Id becomes an `Async__c` row with
   `Status__c = 'Pending'`, tagged with the Apex class to run and a **thread Id**
   that groups everything enqueued in the same transaction.
2. **A managed thread starts.** Saving the work items kicks off a single
   background Queueable (the "thread") for that group of work.
3. **The thread pulls one batch.** It looks up the next `Pending` work item,
   reads the [configured batch size](#configuration) for your class, and gathers
   up to that many matching work items. It marks them `Running` and runs your
   class's `execute(Set<Id> ids)` with that batch's record Ids.
4. **A finalizer records the outcome.** When the batch finishes, a finalizer
   marks those work items `Done` and **chains the next batch**. Because chaining
   happens one batch at a time, you never violate the "one child Queueable" rule,
   and each batch gets a fresh set of governor limits.
5. **Failures are captured, not lost.** If a batch throws, its work items are
   marked `Error` with the message and stack trace saved on the record, and the
   thread continues. Nothing fails silently.

Work is processed **first-in, first-out** (with an optional priority — see
below), so jobs run in roughly the order they were requested.

## Configuration

By default the framework processes **5 work items per batch**. You can change
that per Apex class — without touching code — using the `Async_Config__mdt`
custom metadata type. Create a record with:

| Field | Meaning |
| --- | --- |
| `Apex__c` | The exact name of your `Async` subclass, e.g. `HelloWorldAsync`. |
| `Batch_Size__c` | How many work items one batch (one `execute` call) processes. |

For example, a record with `Apex__c = HelloWorldAsync` and `Batch_Size__c = 50`
makes each `execute` call receive up to 50 record Ids instead of 5.

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

## Examples

### Background-update a field on many records

```apex
public with sharing class FlagStaleContactsAsync extends Async {
    public override void execute(Set<Id> ids) {
        List<Contact> contacts = [SELECT Id, Description FROM Contact WHERE Id IN :ids];
        for (Contact contact : contacts) {
            contact.Description = 'Reviewed by background job';
        }
        update contacts;
    }
}
```

Enqueue it from anywhere — a service method, a button controller, even a trigger
handler:

```apex
List<Contact> stale = [SELECT Id FROM Contact WHERE LastActivityDate < LAST_N_DAYS:90];
Async.enqueue(FlagStaleContactsAsync.class, stale);
```

If `stale` returns 4,000 records, the calling transaction simply records 4,000
work items. With the default batch size, the framework then runs 800 background
batches of 5, one chaining to the next, each within its own limits.

### A job that calls out

`Async` already allows callouts, so a subclass can integrate with an external
system without extra wiring:

```apex
public with sharing class SyncAccountsAsync extends Async {
    public override void execute(Set<Id> ids) {
        List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id IN :ids];
        for (Account account : accounts) {
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:My_Service/accounts');
            request.setMethod('POST');
            request.setBody(JSON.serialize(account));
            new Http().send(request);
        }
    }
}
```

Because callouts are limited per transaction, this is a class where a **small
batch size** matters — size the `Async_Config__mdt` batch to stay under the
callout limit for a single execution.

## Testing

You test an `Async` subclass without waiting for real background jobs by
swapping in `AsyncMock`, which lets the whole chain run inside
`Test.startTest()` / `Test.stopTest()`. The pattern mirrors the framework's own
`AsyncTest`:

```apex
@istest
private class FlagStaleContactsAsyncTest {

    @istest
    static void testFlagsContacts_inBackground() {
        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = 'Test1'),
            new Contact(LastName = 'Test2')
        };
        insert contacts;

        // canEnqueue() lets the async chain actually run during the test.
        AsyncMock mock = new AsyncMock().canEnqueue();
        Async.setMock(mock);

        Test.startTest();
            Async.enqueue(FlagStaleContactsAsync.class, contacts);
        Test.stopTest();

        // Every work item should have completed.
        for (Async__c workItem : [SELECT Status__c FROM Async__c]) {
            Assert.areEqual('Done', workItem.Status__c,
                'Expected every async work item to finish as Done.');
        }

        // And the job's side effect should have happened.
        for (Contact contact : [SELECT Description FROM Contact]) {
            Assert.areEqual('Reviewed by background job', contact.Description,
                'Expected the async job to update each contact.');
        }
    }
}
```

What each piece does:

- **`new AsyncMock().canEnqueue()`** turns on enqueuing inside a test. By
  default the framework refuses to enqueue its thread while a test is running (so
  you don't accidentally fire background work); `canEnqueue()` opts this test in
  so the chain runs and drains during `Test.stopTest()`.
- **`Async.setMock(mock)`** installs the mock services for the transaction.
- **Enqueue inside `Test.startTest()`** and let `Test.stopTest()` flush the
  asynchronous work, then assert on two things: the **work item statuses**
  (proof the framework ran your job to completion) and the **side effect** of
  your `execute` (proof your logic did the right thing).

You can also define the subscriber class as a small inner class in the test when
you only need it for the test, exactly as `AsyncTest` does with its
`MyTestAsync` inner class.

## Gotchas & Notes

- **`enqueue` does not run your code inline.** It records work items and returns.
  Your `execute` runs later, in the background. Don't assert on its results in
  the same synchronous block — in a test, assert after `Test.stopTest()`.
- **`execute` receives a batch, not the full set.** Write it to handle whatever
  `ids` it is given, bulk-safely. Query once for the batch; never query or DML
  inside a per-record loop.
- **Work from Ids, not captured records.** Even when you enqueue a
  `List<SObject>`, only the Ids are kept. Re-query inside `execute` so you act on
  current data.
- **Override only `execute(Set<Id> ids)`.** The rest of the class is framework
  machinery. As a subscriber you should not need to touch it.
- **Tune batch size to the work.** Heavy jobs (callouts, large DML, CPU) need
  smaller batches to stay inside one Queueable's limits; light jobs can use
  larger batches to finish faster. Set it per class in `Async_Config__mdt`;
  the default is 5.
- **Errors are recorded, not hidden.** A failing batch marks its work items
  `Error` with the message and stack trace on the `Async__c` record — check there
  when a background job doesn't do what you expected.
