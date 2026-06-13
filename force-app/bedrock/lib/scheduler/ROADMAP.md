# Scheduler - Roadmap

Scheduler now has an MVP framework in `force-app/bedrock/lib/scheduler`. Treat
this roadmap as planned direction beyond the implemented contract. Cross-cutting
sequencing and the "keep the pools separate" principle live in the repo root
`ROADMAP.md`.

The current implementation provides twelve physical scheduled Apex jobs that
together fire one heartbeat every five minutes. Each heartbeat translates
`Scheduler_Config__mdt` into `Scheduler__c` when configuration changes, then
enqueues due logical jobs as Queueables. It supports `Minutes`, `Hours`, and
`Days` cadence units using `Frequency_Value__c` and `Last_Executed_At__c`.

## Current MVP Scope

- Twelve physical scheduler slots via the top-level `SchedulerTick` entrypoint.
- Logical jobs extend `Scheduler` and override `execute()` with no parameters.
- Each due logical job runs as its own Queueable.
- `Scheduler_Config__mdt` defines Apex class, enabled state, frequency, and
  frequency value.
- `Scheduler__c` stores translated runtime state, including last execution and
  last error. It also stores the metadata hash used to short-circuit
  translation when runtime rows already match the current config.
- Outages self-heal by running overdue jobs once on the next scheduler tick.

## Near-Term Integration

- Add first-party scheduler jobs for Async job archiving.
- Add first-party scheduler jobs for LimitsService resume monitoring.
- Add default metadata records for those jobs once their concrete classes exist.
- Revisit Async archiving's shape if it needs a recordless system-task path
  instead of direct scheduler execution.

## Future Roadmap

- **Missed tick and backfill policy:** decide whether any job needs replay of
  each missed occurrence, or whether "run once when overdue" remains the
  framework default. If replay is needed, add explicit per-job configuration so
  maintenance jobs do not accidentally create backlog surges.
- **Concurrency protection:** cap how many logical scheduler Queueables can be
  enqueued per tick, likely using the future ThreadService and LimitsService
  layer rather than local scheduler-only limits.
- **Additional cadences:** consider time-of-day windows, weekday/monthly
  schedules, and priority ordering only after real jobs prove the need.
- **Operational state:** consider next planned run, last attempted run,
  consecutive failure count, and paused-until fields on `Scheduler__c` when
  correction logic needs them.
- **Admin visibility:** add a simple console view for enabled jobs, last run,
  last error, and next due estimate after the runtime model settles.

## Non-Goals For MVP

- No replay of every missed tick.
- No per-job Salesforce cron schedules.
- No multiple physical scheduler slots.
- No queueable concurrency cap beyond platform limits.
- No wall-clock alignment for hourly or daily jobs.
