# Thread Service — Agent Guide

Component guide for the shared `Thread` service. Global conventions live in the
repo root `AGENTS.md`. Planned follow-up work lives in `./ROADMAP.md`; treat
roadmap notes as intended direction, not implemented contract.

## What it is

`Thread` is shared concurrency infrastructure used by `Async` today. It creates
and tracks `Thread__c` records, stores the current transaction's thread id in a
static service, and controls when a Queueable chain may start or hand off to the
next pending thread.

## Current shape

- `Thread.currentOrCreate()` creates a `Thread__c` in `Pending` status through
  `DML` and caches its Id for the transaction.
- `Thread.enqueue()` starts the current thread only from a synchronous,
  non-finalizer context, only once per transaction, and only when the current
  user is below `Async.settings.maxThreads()`.
- `Async.SettingsService.maxThreads()` reads `Async_Settings__c.Max_Threads__c`
  and defaults blank or non-positive values to `1`.
- `Thread.continueCurrent()` is called from the `Async.JobWatcher` finalizer.
  If the current thread still has pending `Async__c` work it continues or
  restarts the same chain based on the failure threshold. If the current thread
  is drained, it marks that `Thread__c` `Done`, selects the oldest current-user
  pending thread, locks that row with a second `FOR UPDATE` query, and starts it
  when a slot is available.
- `Thread.QueryService` owns `Thread__c` reads: pending-thread claim and running
  thread count. Running counts are scoped to `CreatedById = UserInfo.getUserId()`.
- `ThreadMock` provides test seams for `canEnqueue`, mock thread ids, pending
  thread results, and running-thread counts.

## Schema

The implemented schema is `Thread__c` with `Status__c` values `Pending`,
`Running`, and `Done`. `Async__c.Thread__c` is a lookup to `Thread__c`.

The roadmap still tracks future details such as Event consumption, Event-over-
Async priority on the same thread, Limiter integration, and starvation recovery.
