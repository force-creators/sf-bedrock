# Scheduler — Roadmap

A future Bedrock framework. This folder has no implemented code yet — it is
proposed work. Cross-cutting roadmap principles and feature sequencing live in
the repo root `ROADMAP.md`. Keep this framework's logical execution pool
separate from Async and Event — do not collapse their queues, job tracking, or
policy without an explicit plan.

These are intended designs, not finalized public APIs. Ask before locking
names, schemas, metadata objects, or behavior that does not exist yet.

## Scheduler

Status: MVP1 is the next framework the owner expects to build (it unblocks Async
Job Archiving and the LimitsService resume monitor — see `../async/ROADMAP.md`
and `../limits-service/ROADMAP.md`).

An async-backed scheduler that avoids consuming one Salesforce scheduled job
slot per logical scheduled task.

**MVP1 scope (just enough to unblock Async):**

- One scheduled Apex job firing approximately every 15 minutes.
- Reads a `Scheduler_Config__mdt` row to decide what work to dispatch.
- Enough runtime to trigger the Async limits-resume check and the archive job.

**Full framework (deferred):**

- A small fixed number of Salesforce scheduled jobs, likely three slots.
- Run logical jobs from `Scheduler_Config__mdt`.
- Cadence rules: every X minutes (five-minute intervals), every X hours, every X
  days.
- Track due work and recovery state with `Scheduler_Job__c`.
- Enqueue due work async; pass a scheduler "tic" through constructors as the
  frame of reference for the next run.
- Its own logical execution pool, separate from Async and Event. Design
  defensively for Salesforce outages and missed windows.
