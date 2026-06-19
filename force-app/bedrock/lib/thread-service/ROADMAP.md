# Thread Service — Roadmap

`Thread`, `Thread__c`, and `ThreadRunner` are implemented shared infrastructure.
The current contract is the Apex source, metadata, and `AGENTS.md`; this roadmap
tracks remaining shared-thread follow-up.

## Current Baseline

- `Thread__c` is the shared lane/worker record for threaded Bedrock work.
- `ThreadRunner` dispatches work through pool-specific dispatchers.
- Async and EventRelay both use Thread pools.
- `Thread_Settings__c` owns capacity and recovery settings.
- `Thread.recover()` resumes paused threads and restarts stale recoverable
  threads when limits and capacity allow.
- Limiter checks protect unsafe Queueable starts and recovery.

## Remaining Work

- **Pool policy:** keep pool-specific business behavior in dispatchers, not in
  `Thread`.
- **Fairness:** refine how pools share capacity if real org usage shows one pool
  can crowd another.
- **Operator visibility:** expose enough thread state to explain `Pending`,
  `Running`, `Paused`, and stale-recovered work.
- **Recovery tuning:** revisit recovery thresholds and batch size only after
  operational usage shows the defaults are too conservative or too aggressive.
- **EventRelay priority over Async:** preserve linear thread behavior while
  allowing urgent publication work to run ahead of ordinary backlog when needed.

## Non-Goals For Now

- No framework-specific work-item logic in `Thread`.
- No separate lane-owner object while `Thread__c` works as the shared primitive.
- No hard guarantee that a soft concurrency cap can never overshoot by a small
  amount under high volume.
