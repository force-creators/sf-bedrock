# Async — Roadmap

`Async` is implemented in this folder. The current contract is the Apex source,
metadata, and `AGENTS.md`; this roadmap tracks remaining Async-specific work.

Shared thread capacity, recovery, and limiter behavior live with
`../thread-service`. Scheduler integration lives with `../scheduler`.

## Deliberate Trade-Offs

These are intentional omissions, recorded so they are not re-litigated.

- **Terminal-failure alerting:** when retries exhaust, items rest in `Error`.
  Alerting is left to subscribers and admin tooling.
- **Subscriber finalizer failures:** the framework leans on Finalizers to catch
  otherwise-uncatchable failures. A subscriber whose own DML throws inside the
  finalizer path can still strand work; recovery should remain conservative.
- **Bulk-enqueue chunking:** enqueuing more than about 10k Ids in one transaction
  hits Salesforce DML row limits. The framework does not hide that platform
  boundary.

## Remaining Work

- **Performance tracking:** decide whether to add timing and limits fields such
  as queued, started, completed, backlog duration, execution duration, CPU, and
  SOQL count. Gate any writes behind an Async setting if the fields are added.
- **Default batch size setting:** `Async.MetadataService` currently falls back to
  `Batch_Size__c = 5` when no `Async_Job__mdt` row exists. If a setting is still
  useful, add only the field and behavior needed for that fallback.
- **Console Completed tab:** show `Async__c` records in `Done` status with useful
  operational columns.
- **Console Archive tab:** show `Async_Archive__c` records and expose any manual
  archive action only if the console needs it.
- **Archive operations docs:** document `Archive_Threshold_Hours__c`,
  `Enable_Archive_Cleanup__c`, `Max_Archive_Age__c`, `AsyncArchiveJob`,
  `AsyncArchiveBatch`, and `AsyncArchiveCleanupBatch` in the appropriate docs
  page.

## Non-Goals For Now

- No per-call priority argument on `Async.enqueue`; priority stays
  configuration-driven through `Async_Job__mdt`.
- No Async-owned thread cap; `Thread_Settings__c` owns capacity.
- No Async-specific recovery monitor separate from `Thread.recover()`.
