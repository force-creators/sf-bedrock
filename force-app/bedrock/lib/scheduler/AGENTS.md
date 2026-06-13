# Scheduler — Agent Guide

Component guide for the `Scheduler` framework. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Planned Scheduler work beyond this
MVP lives in `./ROADMAP.md`. Inspect the code in this folder before depending
on exact method behavior.

## What it is

`Scheduler` is a lightweight recordless job framework. Twelve physical
scheduled Apex jobs fire one shared heartbeat every five minutes. Each heartbeat
checks whether `Scheduler_Config__mdt` changed, translates metadata rows into
`Scheduler__c` runtime rows when needed, and then invokes each enabled logical
scheduler job that is due.

## Current shape

- `Scheduler` is a `virtual` base class that also implements `Queueable`.
  Subclasses override `execute()` with no parameters; the framework wrapper
  handles queueable execution and runtime-state updates.
- `SchedulerTick` is the top-level physical `Schedulable` entrypoint. It calls
  `Scheduler.tick()` directly so one tick can enqueue many logical queueables.
- `Scheduler.schedule()` replaces existing `Bedrock Scheduler %` jobs and then
  creates twelve scheduled Apex jobs at the five-minute marks in each hour.
- `Scheduler.JobService` owns the tick flow: compare metadata hash, translate
  `Scheduler_Config__mdt` into `Scheduler__c`, then re-query enabled jobs and
  enqueue only the jobs whose cadence is due.
- `Scheduler.MetadataService` reads `Scheduler_Config__mdt` and computes the
  stable config hash used to short-circuit translation when nothing changed.
- `Scheduler.SettingsService` reads and writes the org-level
  `Scheduler_Settings__c` row that stores the last metadata hash and
  translation timestamp.
- `Scheduler.QueryService` owns `Scheduler__c` reads through `Query`.
- `SchedulerMock` provides lightweight in-memory seams for metadata, query, and
  settings behavior in unit tests.

## Schema

- `Scheduler_Config__mdt` describes logical jobs (`Apex__c`, `Is_Enabled__c`,
  `Frequency__c`, `Frequency_Value__c`). `Interval__c` is legacy metadata and
  is not read by current Scheduler code.
- `Scheduler__c` persists one runtime row per metadata job
  (`Config_Key__c`, `Apex__c`, `Is_Enabled__c`, `Frequency__c`,
  `Frequency_Value__c`, `Last_Executed_At__c`, `Last_Error__c`).
- `Scheduler_Settings__c` stores org-level scheduler state
  (`Metadata_Hash__c`, `Translated_At__c`).

## Notes

- Removed metadata rows are not deleted from `Scheduler__c` in this MVP. They
  are disabled so runtime history remains available.
- Cadence is based on `Last_Executed_At__c`. `Minutes`, `Hours`, and `Days`
  jobs run once they are overdue by `Frequency_Value__c`. Minute values are
  clamped to a minimum of five minutes.
- Run or enqueue failures for one logical row are recorded on that row and do
  not stop the rest of the tick.
- Outage recovery is intentionally simple: overdue jobs run once on the next
  successful tick. The framework does not replay every missed occurrence.
- There is no missed-tic replay, outage backfill, or slot protection yet.
- Future discussion for missed-tic replay, concurrency caps, and additional
  cadence types belongs in `ROADMAP.md`, not in the implemented contract.
