# Async — Agent Guide

Component guide for the `Async` framework. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Planned Async work — Retry,
Priority, Performance Tracking, SettingsService, MetadataService, Job
Archiving, and the Async Console UI — lives in `./ROADMAP.md`. Inspect the code
in this folder before depending on exact method behavior.

## What it is

`Async` (in `force-app/bedrock/lib/async`) is an implemented Queueable-based
async framework, not just a base class. It processes record work in chains of
Queueables tracked on the `Async__c` custom object. The pieces below exist
today; inspect the code before depending on exact behavior.

## Current shape

- `Async` is a `virtual` class implementing `Queueable` and
  `Database.AllowsCallouts`. Subclasses override `execute(Set<Id> ids)`.
- Three injectable service singletons drive behavior: `Async.jobs`
  (`JobService`), `Async.work` (`WorkService`), and `Async.queries`
  (`QueryService`). `Async.setMock(AsyncMock)` swaps all three for tests.
- `Async.enqueue(Type, List<SObject>)` and `Async.enqueue(Type, Set<Id>)` create
  one `Async__c` work item per record Id (via `Pluck.ids`) in `Pending` status,
  tagged with the current request's thread id and the target Apex type.
- `Async.stage(Type, ...)` buffers work by Apex type on `WorkService.buffer`
  without DML; `Async.flush()` drains the buffer. If a `JobWatcher` finalizer is
  active (`shouldDefer()` is true because `jobs.watcher != null`), `flush()`
  defers the buffered work into `JobWatcher.deferredWork` so it is inserted from
  the finalizer via `createDeferredWork()` after the current job succeeds;
  otherwise it inserts the work items immediately through `WorkService.create`.
- `AsyncTrigger` on `Async__c` runs `AsyncTriggerHandler` (extends
  `TriggerHandler`). After insert it starts a thread; after update it re-enqueues
  when `AsyncFilters.shouldRetry` detects an `Error` row flipped back to
  `Pending`.
- `AsyncThread` is a Queueable that adopts a thread id and asks
  `jobs.enqueueNextJob()` to dispatch the next pending work for that thread.
- `JobService.enqueueNextJob()` selects the next pending work item FIFO
  (`ORDER BY Priority__c DESC, CreatedDate ASC`), reads `Async_Config__mdt` for
  the batch size (default 5), pulls a matching batch of same-Apex work items,
  instantiates the Apex job by name, and enqueues it as `Running`.
- `Async.JobWatcher` (a `Finalizer`) marks the batch `Done` and chains the next
  job on success, or records `Error` with truncated message/stack trace and
  re-enqueues on failure.
- `WorkService` owns the `Async__c` status transitions (`create`, `running`,
  `complete`, `fail`, `retry`) through `DML`. `QueryService` owns all
  `Async__c` and `Async_Config__mdt` reads through `Query`.
- `AsyncMock` provides test subclasses of the three services, including a
  `canEnqueue()` toggle and a bounded `maximumQueueableStackDepth` thread start.
- `Async.AsyncException` is the framework's error type.

## Schema

This framework relies on the `Async__c` object (fields `Apex__c`,
`Record_Id__c`, `Status__c`, `Thread__c`, `Priority__c`, `Error_Message__c`,
`Error_Stack_Trace__c`) and the `Async_Config__mdt` type (`Apex__c`,
`Batch_Size__c`), both under `force-app/bedrock/lib/async/objects`.

## Composition

`Async` runs on `DML`, `Query`, and `Pluck` today, and builds on
`TriggerHandler` via `AsyncTriggerHandler`. The planned multithreading layer
that `Async` will consume (shared `ThreadService` / `Thread_Context__c`) lives
in `../thread-service/ROADMAP.md`; the shared limits gate lives in
`../limits-service/ROADMAP.md`.
