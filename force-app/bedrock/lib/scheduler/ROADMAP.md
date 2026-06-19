# Scheduler — Roadmap

`Scheduler` is implemented in this folder. The current contract is the Apex
source, metadata, and `AGENTS.md`; this roadmap tracks only follow-up work.

## Current Baseline

- Twelve physical scheduled Apex jobs provide one heartbeat every five minutes.
- `Scheduler_Job__mdt` metadata is translated into `Scheduler__c` runtime rows.
- Due logical jobs run as Queueables.
- Existing cadence units are `Minutes`, `Hours`, `Days`, `Weeks`, and `Months`.
- Overdue jobs self-heal by running once on the next scheduler tick.
- First-party metadata exists for Thread recovery and Async archiving.

## Remaining Work

- **Limiter resume visibility:** decide whether Thread recovery is enough for
  paused-work resumption or whether a separate Limiter-focused operator view is
  useful.
- **Missed tick policy:** keep "run once when overdue" as the default. Add replay
  only if a concrete scheduled job proves it needs every missed occurrence.
- **Scheduler throttling:** consider a cap on logical Queueables per tick if real
  org usage shows scheduler fan-out can crowd other work.
- **Additional cadences:** consider time-of-day windows, weekday rules, and
  priority ordering only after existing cadence types prove too narrow.
- **Operational state:** add fields such as consecutive failure count or
  paused-until only when correction logic needs them.
- **Admin visibility:** add a simple console view for enabled jobs, last run,
  last error, and next due estimate after the runtime model settles.

## Non-Goals For Now

- No replay of every missed tick by default.
- No per-job Salesforce cron schedules.
- No more physical scheduler slots unless the five-minute heartbeat is no longer
  enough.
- No wall-clock alignment for hourly or daily jobs.
