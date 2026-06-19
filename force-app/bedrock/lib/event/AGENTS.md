# EventRelay — Agent Guide

Component guide for the `EventRelay` framework. Global conventions
(Apex style, testing rules, Salesforce MCP validation, architecture layers) live
in the repo root `AGENTS.md`. Planned and historical event notes live in
`./ROADMAP.md`; inspect the code in this folder before depending on exact
behavior.

## What it is

`EventRelay` is Bedrock's durable event framework. It stores outbound
publication work and inbound processing work as `Event__c` rows, then drains
those rows through shared `Thread__c` lanes using `ThreadRunner`.

Use `EventRelay.publish(...)` when a Platform Event or generic payload should
leave the org with durable status. Use `EventRelay.ingest(...)` when a Platform
Event or generic payload should be processed by Apex later with retryable,
inspectable status.

## Current shape

- `EventRelay.publish(...)` creates publish work in the `EventRelayPublish`
  pool. Platform Event SObjects use the built-in platform event publisher by
  default; generic payloads require route metadata.
- `EventRelay.ingest(...)` creates process work in the `EventRelayProcess` pool.
  Explicit handler classes are allowed, and metadata routes can select handlers.
- `EventRelay.stage(...)` and `EventRelay.flush()` buffer publish-side
  Platform Event SObjects in the current transaction before creating work.
- `Event__c` stores payload chunks, route, job type, lane key, retry count,
  status, and error details.
- `Event_Config__mdt` controls metadata-backed routes, Apex class names,
  idempotency key paths, batch size, retry cap, direction, source type, and
  active state.
- `EventRelay_Wake__e` wakes pending EventRelay lanes. The wake trigger calls
  `EventRelay.wake()`, which asks `Thread` to fill publish and process pool
  capacity.
- `EventRelay.Handler` is the inbound processing extension point.
  `EventRelay.Publisher` is the outbound publication extension point.
- `EventRelay.Route.apexClass` is the current internal name for the class that
  executes work. `Route.publisherClass` remains as a compatibility alias.
- `EventRelay` remains the public facade and compatibility container. Several
  formerly nested service implementations now live in focused top-level Apex
  classes named `EventRelay*Service`; the nested `EventRelay.*Service` classes
  remain as thin wrappers so existing tests and subscriber mocks keep compiling.
- Put payload serialization/chunking in `EventRelayPayloadService`, Event
  metadata reads in `EventRelayMetadataService`, route resolution in
  `EventRelayRouteService`, durable work creation/status/idempotency/retry
  behavior in `EventRelayWorkService`, Event work SOQL/batching in
  `EventRelayQueryService`, thread-lane job dispatch in
  `EventRelayJobService`, handler/publisher class lookup in
  `EventRelayHandlerService` / `EventRelayPublisherService`, wake publication in
  `EventRelay.WakeService`, and defaults in `EventRelay.SettingsService`.
- `EventRelay*Smoke*` classes are end-to-end smoke fixtures used by tests to
  exercise real Queueable and Platform Event behavior. Do not treat them as
  recommended subscriber naming patterns.

## Vocabulary

- A **work item** is one `Event__c` row.
- A **route** is the resolved publisher or handler choice.
- A **lane** is the FIFO boundary. It is stored as `Thread_Key__c`.
- A **thread** is the `Thread__c` worker record that owns and drains a lane.
- `publish` is outbound durable work.
- `ingest` is the public API for inbound durable work.
- `process` is the stored job type for ingested work.
- `stale` means duplicate idempotent work that is saved for audit but not run.

## Composition

`EventRelay` runs on `DML`, `Query`, `Generic`, `Thread`, `ThreadRunner`, and
`Limiter`. Thread owns lane lifecycle, capacity, handoff, and recovery.
EventRelay owns payload storage, route resolution, publish/process job
execution, stale duplicate handling, retry transitions, and payload
serialization.

Do not move EventRelay-specific behavior into `Thread`. When pool behavior is
needed, prefer extending the `ThreadRunner.Dispatcher` policy hooks.
