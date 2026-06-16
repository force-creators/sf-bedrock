---
layout: ../layouts/DocsLayout.astro
title: Thread | sf-bedrock docs
description: Shared thread records and per-user concurrency caps for Bedrock async work.
eyebrow: Tools
heading: Thread
lede: Thread tracks logical background work chains with `Thread__c`, gates how many may run for a user, and hands off from one pending thread to the next.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Thread Cap
    href: "#thread-cap"
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

`Thread` is the shared service behind Bedrock background work. It creates
`Thread__c` records, remembers the current transaction's thread, starts work
only when the current user has an available slot, and hands off from a drained
thread to the next pending thread.

Most application code does not call `Thread` directly. You usually use
`Async.enqueue(...)`, and Async assigns work items to the current thread for you.

**Use `Thread` when** you are working on Bedrock framework internals,
framework-level tests, or console/admin surfaces that need to explain thread
state.

**Reach for `Async` instead when** you are writing subscriber work. Async owns
the public record-driven background job API.

## Quickstart

Set the concurrency cap with `Thread_Settings__c.Max_Threads__c`. Blank, `0`, and
negative values default to `1`.

| Setting | Effect |
| --- | --- |
| `Max_Threads__c = 1` | One running thread chain. Pending threads drain one after another. |
| `Max_Threads__c = 5` | Up to five running thread chains. Separate enqueueing transactions can drain in parallel. |

Then enqueue work normally:

```apex
Async.enqueue(SyncCustomerAsync.class, customerAccounts);
```

Async creates a `Thread__c` for the transaction, writes `Async__c` work items
against that thread, and starts the thread when a slot is available.

## Examples

### Watch a serial backlog

With `Max_Threads__c = 1`, five separate enqueueing transactions create five
`Thread__c` rows. One becomes `Running`; the rest stay `Pending`. When the
running thread drains, Bedrock marks it `Done`, claims the oldest pending thread
for the same user, and starts it.

### Increase throughput for a service user

Set an org default or per-user custom setting override for an integration or automation user:

| Field | Value |
| --- | --- |
| `SetupOwnerId` | Service user Id |
| `Max_Threads__c` | `5` |

Work created by that user can now drain across multiple threads. Work created in
one transaction still stays on one thread; parallelism comes from separate
transactions.

## Thread Cap

The cap is counted by querying `Thread__c` rows in `Running` status for the
current user. It is intentionally a soft cap: if several transactions start at
the same time, Salesforce can briefly allow a small overshoot.

Thread statuses are simpler than work-item statuses:

| Status | Meaning |
| --- | --- |
| `Pending` | The thread has work, but no Queueable chain is currently running it. |
| `Running` | A Queueable chain is actively draining this thread. |
| `Done` | The thread has no pending work left. |

Individual `Async__c` work items still carry their own statuses:
`Pending`, `Running`, `Done`, and `Error`.

## Testing

Use `ThreadMock` only for framework-level tests. Subscriber tests should usually
test the `Async` job directly or use `AsyncMock`.

```apex
@istest static void threadStartsWhenSlotIsAvailable() {
    AsyncMock mock = new AsyncMock()
        .canEnqueue()
        .mockThreadIds();
    Async.setMock(mock);
    Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
    mock.threads.runningThreads(1);

    Thread.enqueue();

    Assert.areEqual(
        1,
        mock.threads.service.startCalls,
        'Expected Thread.enqueue to start work when the user is below the thread cap.'
    );
}
```

`Async.setMock(mock)` also installs the mock thread services, so framework tests
can keep Async and Thread behavior in one small test setup.

## How It Works

Three ideas explain the service.

**One: the current transaction has one thread.** `Thread.currentOrCreate()`
creates a `Thread__c` in `Pending` status and caches its Id for the transaction.
Async work created in that transaction uses that thread.

**Two: the cap gates starts, not inserts.** If no slot is available, work items
and their `Thread__c` remain `Pending`. The framework does not throw away work
just because all slots are busy.

**Three: handoff keeps the backlog moving.** When a Queueable chain drains its
thread, the finalizer marks the thread `Done`, selects the oldest pending thread
for the same user, locks that row with `FOR UPDATE`, marks it `Running`, and
starts the next chain.

## Public API

> **A note on access modifiers.** In Apex, an omitted modifier means `private`.
> Members listed here without an access modifier are private to the class and
> not accessible from outside it. `@testVisible` members are private in
> production but accessible in test classes. `Thread` is framework-owned; these
> methods are documented so the async runtime can be understood, not because app
> teams should build business logic on them.

### Static Methods

| Method | Signature | Description |
| --- | --- | --- |
| `currentId` | `public static Id currentId()` | Returns the current transaction's cached thread Id, or `null`. |
| `currentOrCreate` | `public static Id currentOrCreate()` | Returns the current thread Id, creating a `Thread__c` when needed. |
| `setCurrent` | `public static void setCurrent(Id threadId)` | Sets the current thread Id. Used by framework Queueables/finalizers. |
| `enqueue` | `public static void enqueue()` | Starts the current thread when the context and cap allow it. |
| `continueCurrent` | `public static void continueCurrent()` | Continues, completes, or hands off the current thread. |
| `continueCurrent` | `public static void continueCurrent(Integer failures)` | Same as `continueCurrent()`, carrying the current failure streak. |
| `deleteDrained` | `public static void deleteDrained(Set<Id> threadIds)` | Framework cleanup helper for drained thread rows. Not a subscriber-facing entry point. |

### Schema

**`Thread__c`** (custom object):

| Field | Purpose |
| --- | --- |
| `Status__c` | Thread lifecycle status: `Pending`, `Running`, `Done`. |

**`Async__c.Thread__c`** is a lookup to `Thread__c`.

**`Thread_Settings__c.Max_Threads__c`** controls running thread capacity. Blank
or non-positive values default to `1`.

Operators should usually inspect and recover runtime state through the Bedrock
Console and Admin Setup & Operations guidance, not by editing `Thread__c` rows
directly.

## Notes & Edge Cases

- **One transaction creates one thread.** A single large enqueue does not shard
  itself across multiple threads.
- **The cap is soft.** Concurrent transactions can briefly race past it.
- **Pending is normal.** If no slot is available, the thread waits in `Pending`
  until another chain drains and hands off.
- **Handoff is FIFO by creation time.** The service first selects the oldest
  pending thread, then locks that row by Id in a second query.
- **There is no reaper yet.** A platform incident, aborted job, or finalizer
  failure could theoretically leave a thread stuck in `Running`; recovery is a
  future hardening item.
