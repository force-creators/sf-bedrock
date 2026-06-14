# sf-bedrock Roadmap

This file holds only the **cross-cutting** roadmap: the shared principles that
span frameworks and the feature sequencing across them. Each framework's
detailed roadmap now lives next to its code in
`force-app/bedrock/lib/<component>/ROADMAP.md`. AGENTS.md (root and per
component) describes only implemented tools; anything not yet built lives in a
component ROADMAP.

These are intended designs, not finalized public APIs. Inspect current code in
`force-app/bedrock/lib` before building, and ask before locking names, schemas,
metadata objects, or behavior that does not exist yet. Prefer one clear bite at
a time over large speculative framework builds.

## Cross-cutting principle: keep the pools separate

Keep each framework's logical execution pool (Async, Event, Scheduler) separate
— do not collapse their queues, job tracking, or policy without an explicit
plan. The thread-slot concurrency layer (`Thread` / `Thread__c`)
and `Limiter` are deliberately *shared* infrastructure beneath those
separate pools; sharing a mechanism is not collapsing pools. Extend `AsyncMock`
and the service override surface only when a concrete test needs a new seam;
keep the exposed levers intentionally light.

## Component roadmaps

| Component | Roadmap | Status |
|---|---|---|
| Async (features + Console UI) | [`lib/async/ROADMAP.md`](force-app/bedrock/lib/async/ROADMAP.md) | Active — Retry, Priority, Performance Tracking, SettingsService, MetadataService, Job Archiving, Completed/Archive tabs |
| Thread / Multithreading | [`lib/thread-service/ROADMAP.md`](force-app/bedrock/lib/thread-service/ROADMAP.md) | Shared infra — Async cap + handoff implemented; Event/pool follow-up pending |
| Limiter | [`lib/limiter/ROADMAP.md`](force-app/bedrock/lib/limiter/ROADMAP.md) | Shared infra — org-health gate |
| Scheduler | [`lib/scheduler/ROADMAP.md`](force-app/bedrock/lib/scheduler/ROADMAP.md) | Active MVP — cadence, metadata translation, runtime state |
| Event | [`lib/event/ROADMAP.md`](force-app/bedrock/lib/event/ROADMAP.md) | Future framework |
| Selector / Selector.Cached | [`lib/selector/ROADMAP.md`](force-app/bedrock/lib/selector/ROADMAP.md) | Future, builds on `Query` / `PlatformCache` |

The Async non-goals and deliberate trade-offs (terminal-failure alerting,
orphaned `Running` reaper, bulk-enqueue chunking) live with the Async roadmap.

## Sequencing at a glance

- **Unblocked now:** Retry, Priority, Performance Tracking, SettingsService,
  MetadataService, Async UI Completed tab.
- **Implemented now:** Multithreading core for Async (cap + handoff; uses
  `Max_Threads__c` and `Thread__c`).
- **Scheduler follow-up:** Job Archiving, Limiter resume monitor,
  Multithreading backlog-starvation recovery.
- **Blocked by Job Archiving:** Async UI Archive tab.
- The owner expects to build **Scheduler MVP1** before finishing Async.
