# EventRelay — Roadmap

`EventRelay` is implemented in this folder. The current contract is the Apex
source, metadata, and `AGENTS.md`; this roadmap tracks only remaining decisions
and follow-up work.

## Current Baseline

- Durable publish and ingest APIs exist on `EventRelay`.
- Work is stored in `Event__c`.
- Routes live in `Event_Config__mdt`.
- Publish and process pools run through shared `Thread__c` lanes and
  `ThreadRunner`.
- EventRelay owns payload storage, route resolution, publish/process execution,
  retries, stale duplicate handling, and payload serialization.

## Remaining Work

- **Operator visibility:** decide what EventRelay-specific console or docs views
  are needed for pending, stale, errored, and retried work.
- **Payload retention:** document or implement guidance for deleting, masking, or
  archiving serialized payloads that may contain sensitive data.
- **Lane configuration:** decide whether route metadata needs more explicit lane
  partition controls for orgs that need parallelism by business key.
- **Stale handling:** keep duplicate idempotency behavior simple. Add TTL,
  sequence, or version handling only when a concrete use case needs it.
- **Fairness:** keep EventRelay publication able to run ahead of ordinary Async
  work when platform-event durability requires it, without letting inbound event
  processing starve other thread pools.
- **Manual retry:** decide whether manual `Error -> Pending` retry preserves the
  existing thread/lane or recomputes routing and lane ownership.

## Non-Goals For Now

- No separate Event lane object while `Thread__c` can remain the shared worker
  primitive.
- No general stream-processing engine.
- No complex routing rules engine until metadata-backed routes prove too narrow.
