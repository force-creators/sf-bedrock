# Async — Roadmap

Planned and future work for the `Async` framework. The implemented framework is
described in `./AGENTS.md`. Cross-cutting roadmap principles and feature
sequencing live in the repo root `ROADMAP.md`.

These are intended designs, not finalized public APIs. Inspect current code in
this folder before building, and ask before locking names, schemas, metadata
objects, or behavior that does not exist yet. Prefer one clear bite at a time
over large speculative framework builds. Extend `AsyncMock` and the service
override surface only when a concrete test needs a new seam; keep the exposed
levers intentionally light.

Two roadmap items that `Async` consumes live in their own component folders
because they are shared infrastructure, not Async internals:

- Multithreading (per-user thread cap + handoff) and the shared `ThreadService`
  / `Thread_Context__c` → `../thread-service/ROADMAP.md`.
- `LimitsService` (org-health gate consulted before enqueuing) →
  `../limits-service/ROADMAP.md`.

## Non-goals & deliberate trade-offs

These are intentional omissions, recorded so they are not re-litigated. They
reflect the mission: stay lightweight and unopinionated while feature-rich,
rather than being everyone's safety net.

- **Terminal-failure alerting.** When retries exhaust, items rest in `Error`;
  the framework raises no alarms. Alerting is left to subscribers via the
  dashboard — alarm thresholds are too company-specific to bake in.
- **Orphaned `Running` reaper.** By design the framework leans on Finalizers to
  catch otherwise-uncatchable failures, which is why the Queueable deliberately
  carries no try/catch and the Finalizer stays intentionally light (mutate
  state, enqueue the next job). A subscriber whose own DML throws inside that
  light path could strand a `Running` item; building a reaper for that is an
  accepted non-goal.
- **Bulk-enqueue chunking.** Enqueuing more than ~10k Ids in one transaction
  hits the platform DML row limit. That is inherent to Salesforce, not specific
  to the framework, and is not worked around or advertised against.

---

## Retry — `Retry_Count__c` + bounded auto-retry

Status: unblocked.

**Schema:** add `Retry_Count__c` (Number, default `0`) to `Async__c`; add
`Max_Retries__c` (Number) to `Async_Config__mdt`.

`Retry_Count__c` tracks how many times a work item has been run by the
framework. When `Max_Retries__c` is absent or zero, framework auto-retry is off
for that job type.

**Behavior:**

- In `JobWatcher`'s failure path, a new job-service method
  (`jobs.shouldAutoRetry(...)` or similar) compares `Retry_Count__c` against the
  configured max:
  - Under the cap: `WorkService` increments `Retry_Count__c` and sets
    `Status__c = 'Pending'` so the trigger re-enqueues it.
  - At or over the cap: the work item stays terminal `Error`.
- Manual `Error → Pending` flips remain unbounded and are always honored. They
  are not gated by `Retry_Count__c` and do not increment it.
  `AsyncFilters.shouldRetry` keeps its current behavior unchanged.

## Performance Tracking

Status: unblocked. Toggle depends on SettingsService (`Track_Performance__c`).

**Schema:** new fields on `Async__c`:

- `Queued_At__c` (DateTime) — set when the work item is created (`Pending`).
- `Started_At__c` (DateTime) — set on transition to `Running`.
- `Completed_At__c` (DateTime) — set when the finalizer marks `Done`/`Error`.
- `Backlog_Time_ms__c` (Number) — `Queued_At__c` → `Started_At__c`.
- `Execution_Time_ms__c` (Number) — `Started_At__c` → `Completed_At__c`.
- `CPU_Time_ms__c` (Number) — `Limits.getCpuTime()` at job end.
- `SOQL_Queries__c` (Number) — `Limits.getQueries()` at job end.

`WorkService` populates timestamps during status transitions. The finalizer
reads `Limits` at the point it runs and writes the performance fields alongside
`complete`/`fail`. A `Track_Performance__c` setting can disable the writes when
the overhead is not wanted.

## SettingsService — `Async_Settings__c`

Status: unblocked. Foundational; other features read from it.

Split into two buckets:

**Bucket 1 — infrastructure (standalone deliverable):**

- Create `Async_Settings__c` as a hierarchical custom setting (Org / Profile /
  User), so framework defaults can be overridden per user.
- Add `Async.SettingsService` as a fourth injectable singleton alongside
  `JobService`, `WorkService`, `QueryService`. It reads
  `Async_Settings__c.getInstance()`, caches for the transaction, exposes typed
  accessors, and is mockable via `Async.setMock`.
- Expose a single advanced test hook to set the backing `Async_Settings__c`
  values directly, rather than a wide mock surface — keep the lever light.

**Bucket 2 — field definitions (each feature declares what it reads):**

| Setting field | Consumed by |
|---|---|
| `Limits_Threshold_Pct__c` (Number, default 90) | LimitsService |
| `Archive_After_Days__c` (Number, default 30) | Job Archiving |
| `Default_Batch_Size__c` (Number) | MetadataService (fallback batch size) |
| `Track_Performance__c` (Checkbox, default true) | Performance Tracking |
| `Max_Threads__c` (Number, default 1) | Multithreading (per-user, per-pool cap) |

> `Max_Threads__c` is read by the multithreading layer in
> `../thread-service/ROADMAP.md`; `Limits_Threshold_Pct__c` is read by
> `../limits-service/ROADMAP.md`. SettingsService Bucket 1 unblocks the
> multithreading core.

## MetadataService — cached `Async_Config__mdt` reads

Status: unblocked.

Promote the inline `Async_Config__mdt` queries out of `QueryService` into a
dedicated `Async.MetadataService` inner class with a transaction-level cache.
`QueryService` delegates config reads to it. This removes repeated SOQL for the
same metadata row across a chained-job transaction and gives tests a clean seam
to control config values. Reads `Default_Batch_Size__c` from
`Async.SettingsService` as a fallback when no `Async_Config__mdt` row exists for
a job type.

## Priority — default per job type from config

Status: unblocked.

Dispatch already orders the backlog by `Priority__c DESC`, but nothing currently
sets it, so every work item is equal priority. Add an optional `Priority__c`
(Number) to `Async_Config__mdt`; at enqueue, `WorkService` seeds each work
item's `Priority__c` from that job type's config (via `MetadataService`),
defaulting to the lowest priority when no config row or value exists. Priority is
configuration-driven only — there is no per-call priority argument on
`Async.enqueue`.

## Job Archiving — `Async_Archive__c`

Status: **blocked by Scheduler MVP1** (see `../scheduler/ROADMAP.md`).

**Schema:** create `Async_Archive__c` with the same fields as `Async__c`
(Status, Apex, Record_Id, Thread, Priority, error fields, perf fields, retry
count).

**Behavior:**

- A scheduled job (via Scheduler MVP1) reads `Archive_After_Days__c` from
  `Async.SettingsService` and bulk-moves `Done` work items older than that
  threshold from `Async__c` to `Async_Archive__c`.
- The archive job is itself an `Async` subclass so it runs through the standard
  framework machinery.
- **Thread cleanup:** the archive run records the `threadId` of each archived
  work item and, as its final step, deletes the corresponding
  `Thread_Context__c` records so they do not accumulate.
- The Bedrock Console exposes an ad-hoc "Archive Now" trigger (see Async UI).

---

# Async UI (Bedrock Console)

The console already has **Dashboard**, **Backlog**, **Errors**, and **Jobs**
tabs (Jobs lists the configured `Async_Config__mdt` records). The outstanding UI
work is two new tabs:

## Completed tab

Status: unblocked.

Shows `Async__c` records in `Done` status. Columns: Apex class, Record Id,
Thread, completed timestamp, backlog time, execution time, CPU time, SOQL
queries, retry count. Standard sort/filter; no row actions needed.

## Archive tab

Status: **blocked by Job Archiving**.

Shows `Async_Archive__c` records with the same columns as Completed. Includes an
"Archive Now" button that enqueues an ad-hoc archive run via `Async.enqueue`.
