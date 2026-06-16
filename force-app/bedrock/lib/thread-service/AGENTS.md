# Thread Service — Agent Guide

Component guide for the shared `Thread` service. Global conventions live in the
repo root `AGENTS.md`. Planned follow-up work lives in `./ROADMAP.md`; treat
roadmap notes as intended direction, not implemented contract.

## What it is

`Thread` is shared concurrency infrastructure used by `Async` today. It creates
and tracks `Thread__c` records, stores the current transaction's thread id in a
static service, and controls when a Queueable chain may start or hand off to the
next pending thread. `ThreadRunner` is the shared Queueable/dispatcher layer
that starts a thread and routes work to the pool-specific dispatcher.

## Current shape

- `Thread.currentOrCreate()` creates an `Async` pool `Thread__c` in `Pending`
  status through `DML` and caches its Id for the transaction. New threads store
  `Pool__c`, a request-scoped `Thread_Key__c`, a generated unique
  `Unique_Key__c`, and an initial `Heartbeat__c`.
- `Thread.enqueue()` starts pending threads only from a synchronous,
  non-finalizer context, filling available Queueable/thread slots when
  `Thread_Settings__c.Max_Threads__c` allows more than one running chain.
- `Thread.SettingsService` reads the `Thread_Settings__c` hierarchy setting:
  `Max_Threads__c`, recovery threshold, recovery batch size, recovery limiter
  threshold, and the recovery kill switch. Blank or non-positive numeric values
  fall back to safe defaults.
- Thread starts stamp `Started__c`, refresh `Heartbeat__c`, clear
  `Completed__c`, and advance `Run_Key__c`. Framework runners/finalizers carry
  that run key and must match the current row before they can advance,
  continue, hand off, or complete a thread.
- `Thread.continueCurrent()` is called from the `Async.JobWatcher` finalizer.
  If the current thread still has pending pool work it continues or restarts
  the same chain based on the failure threshold. If the current thread is
  drained, it marks that `Thread__c` `Done`, selects the oldest current-user
  pending thread in the same pool, locks that row with a second `FOR UPDATE`
  query, and starts it when a slot is available. Completion stamps
  `Completed__c` and refreshes `Heartbeat__c`.
- `Thread.recover()` is the scheduled recovery monitor. It finds stale
  non-done threads by `Heartbeat__c`, checks `Thread_Settings__c`,
  `Limiter.isSafe(QUEUEABLE_JOBS, threshold)`, global Thread capacity, and
  pool capacity, advances `Run_Key__c` under lock, asks the dispatcher to
  prepare recoverable work, and either restarts the thread or marks it `Done`.
- `ThreadRunner` owns the queueable entry point. It reads the thread pool and
  dispatches through the matching `ThreadRunner.Dispatcher`; the current
  implemented dispatcher is `Async.ThreadDispatcher`. Dispatchers can expose
  recovery hooks with `hasRecoverableWork(threadId)` and
  `prepareRecovery(threadId)`.
- `Thread.QueryService` owns `Thread__c` reads: pending-thread claim and running
  thread count. Running counts are scoped to `CreatedById = UserInfo.getUserId()`.
- `ThreadMock` provides test seams for `canEnqueue`, mock thread ids, pending
  thread results, and running-thread counts.

## Schema

The implemented schema is `Thread__c` with `Status__c` values `Pending`,
`Running`, and `Done`. `Pool__c` identifies the owning work pool,
`Thread_Key__c` identifies the lane within that pool, `Unique_Key__c` stores a
generated hash for the unique `Pool__c + Thread_Key__c` identity, and
`Run_Key__c` identifies the currently authorized execution chain.
`Started__c`, `Heartbeat__c`, and `Completed__c` make thread lifecycle state
inspectable. `Thread_Settings__c` owns global Thread capacity and recovery
settings. `Async__c.Thread__c` is a lookup to `Thread__c`.

The roadmap still tracks future details such as Event consumption, Event-over-
Async priority on the same thread, Limiter integration, and starvation recovery.
