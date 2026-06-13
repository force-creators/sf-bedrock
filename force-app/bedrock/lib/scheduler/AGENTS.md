# Scheduler — Agent Guide

Component guide for the `Scheduler` framework. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Planned Scheduler work beyond this
MVP lives in `./ROADMAP.md`. Inspect the code in this folder before depending
on exact method behavior.

## What it is

`Scheduler` is a lightweight recordless job framework. Twelve physical
scheduled Apex jobs fire one shared heartbeat every five minutes. Each heartbeat
checks whether `Scheduler_Job__mdt` changed, translates metadata rows into
`Scheduler__c` runtime rows when needed, and then invokes each enabled logical
scheduler job that is due.

## Current shape

- `Scheduler` is a `virtual` base class that also implements `Queueable`.
  Subclasses override `execute()` with no parameters; the framework wrapper
  handles queueable execution and runtime-state updates. It attaches a Queueable
  Finalizer so unhandled queueable failures, including governor limit
  exceptions, are recorded on the runtime row.
- `SchedulerTick` is the top-level physical `Schedulable` entrypoint. It calls
  `Scheduler.tick()` directly so one tick can enqueue many logical queueables.
- `Scheduler.schedule()` replaces existing `Bedrock Scheduler %` jobs and then
  creates twelve scheduled Apex jobs at the five-minute marks in each hour.
- `Scheduler.JobService` owns the tick flow: compare metadata hash, translate
  `Scheduler_Job__mdt` into `Scheduler__c`, then re-query enabled jobs and
  enqueue only the jobs whose cadence is due.
- `Scheduler.MetadataService` reads `Scheduler_Job__mdt` and computes the
  stable config hash used to short-circuit translation when matching runtime
  rows already exist.
- `Scheduler.QueryService` owns `Scheduler__c` reads through `Query`.
- `SchedulerMock` provides lightweight in-memory seams for metadata and query
  behavior in unit tests.

## Schema

- `Scheduler_Job__mdt` describes logical jobs (`Apex__c`, `Enabled__c`,
  `Frequency__c`, `Interval__c`). `Apex__c` is the logical job key.
- `Scheduler__c` persists one runtime row per metadata job
  (`Apex__c`, `Enabled__c`, `Frequency__c`, `Interval__c`, `Hash__c`,
  `Next_Run__c`, `Last_Executed__c`, `Error_Message__c`).

## Notes

- Removed metadata rows are not deleted from `Scheduler__c` in this MVP. They
  are disabled so runtime history remains available.
- Cadence is based on `Next_Run__c`. New or newly enabled jobs wait one full
  configured interval before their first run, so the UI does not report a run
  before one actually happened. Queueable start delay must not push the next due
  window later. `Minutes`, `Hours`, `Days`, `Weeks`, and `Months` jobs run once
  they reach `Next_Run__c`. Minute values are clamped to `5` through `55`,
  day values to `1` through `31`, week values to `1` through `52`, and month
  values to `1` through `12`.
- Run or enqueue failures for one logical row are recorded on that row and do
  not stop the rest of the tick.
- Unhandled Queueable failures are recorded by `Scheduler.JobFinalizer`.
- Outage recovery is intentionally simple: overdue jobs run once on the next
  successful tick. The framework does not replay every missed occurrence.
- There is no missed-tick replay, outage backfill, or slot protection yet.
- Future discussion for missed-tick replay, concurrency caps, and additional
  cadence types belongs in `ROADMAP.md`, not in the implemented contract.
