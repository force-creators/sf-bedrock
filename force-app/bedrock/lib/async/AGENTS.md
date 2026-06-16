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
- Five injectable service singletons drive behavior: `Async.jobs`
  (`JobService`), `Async.work` (`WorkService`), `Async.queries`
  (`QueryService`), `Async.metadata` (`MetadataService`), and
  `Async.settings` (`SettingsService`). `Async.setMock(AsyncMock)` swaps all
  five for tests.
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
- `JobService.enqueueNextJob()` selects the next pending work item by lowest
  assigned priority first (`ORDER BY Priority__c ASC NULLS LAST, CreatedDate ASC`),
  reads `Async_Job__mdt` for
  the batch size (default 5), pulls a matching batch of same-Apex work items,
  instantiates the Apex job by name, and enqueues it as `Running`.
- `WorkService.create(...)` seeds each `Async__c.Priority__c` from the job
  type's `Async_Job__mdt.Priority__c`. Missing config rows or blank priority
  values leave work unassigned, and pending-work queries sort those null
  priorities last.
- `Async.JobWatcher` (a `Finalizer`) marks the batch `Done` and chains the next
  job on success. On failure it delegates to `JobService.handleFailure`, which
  reads each item's `Retry_Count__c`, compares it against the job type's
  `Async_Job__mdt.Max_Retries__c` (via `JobService.shouldAutoRetry`), and
  partitions the batch: items under the cap are re-pended with
  `Retry_Count__c` incremented (`WorkService.autoRetry`) so the chain re-runs
  them, and items at/over the cap (or with no/zero `Max_Retries__c`) record a
  terminal `Error` with truncated message/stack trace. The finalizer then chains
  the next job. Manual `Error → Pending` flips are unbounded, always honored, and
  never increment `Retry_Count__c` (`AsyncFilters.shouldRetry` is unchanged).
- `Async.MetadataService` owns all `Async_Job__mdt` reads behind a
  transaction-scoped cache keyed by Apex name, so repeated config reads for the
  same job type across a chained-job transaction issue one query.
  `QueryService.getJobConfig` delegates to it; no inline `Async_Job__mdt` SOQL
  remains in `QueryService`. When no config row exists for a job type it returns
  a default with `Batch_Size__c = 5` and no priority assignment (the
  `SettingsService` `Default_Batch_Size__c` fallback is still roadmap).
- `Async.SettingsService` owns the transaction-scoped cached read of the
  hierarchical `Async_Settings__c` custom setting. In this Bucket 1
  implementation it exposes only a narrow test seam for seeding the backing
  value; consumer-specific accessors land with the settings fields that need
  them.
- `WorkService` owns the `Async__c` status transitions (`create`, `running`,
  `complete`, `fail`, `retry`, `autoRetry`) through `DML`. `QueryService` owns
  the `Async__c` reads through `Query`; `Async_Job__mdt` reads live in
  `MetadataService`.
- `AsyncMock` provides test subclasses of the five services, including a
  `canEnqueue()` toggle, a bounded `maximumQueueableStackDepth` thread start, a
  `config(Type, Async_Job__mdt)` seam that injects job-type config into the
  `MetadataService` cache without DML, and `seedSettings(Async_Settings__c)` for
  the settings cache.
- `Async.AsyncException` is the framework's error type.

## Schema

This framework relies on the `Async__c` object (fields `Apex__c`,
`Record_Id__c`, `Status__c`, `Thread__c`, `Priority__c`, `Retry_Count__c`,
`Error_Message__c`, `Error_Stack_Trace__c`) and the `Async_Job__mdt` type
(`Apex__c`, `Batch_Size__c`, `Max_Retries__c`, `Priority__c`), plus the
hierarchical custom setting `Async_Settings__c`, all under
`force-app/bedrock/lib/async/objects`. `Retry_Count__c` (default `0`) tracks how
many times the framework has re-run an item; `Max_Retries__c` (absent/`0` ⇒
auto-retry off) caps framework auto-retries per job type. `Priority__c` sorts
from lowest assigned value to highest assigned value, with null/unassigned
priorities last.

## Composition

`Async` runs on `DML`, `Query`, `Pluck`, and `Thread` today, and builds on
`TriggerHandler` via `AsyncTriggerHandler`. The shared thread service lives in
`../thread-service`; the shared limits gate lives in `../limiter/ROADMAP.md`.
