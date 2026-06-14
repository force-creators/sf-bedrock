# Event — Roadmap

A future Bedrock framework. This folder has no implemented code yet — it is
proposed work. Cross-cutting roadmap principles and feature sequencing live in
the repo root `ROADMAP.md`. Event should use the same `Thread__c` container as
Async so chained work remains linear and understandable.

These are intended designs, not finalized public APIs. Ask before locking
names, schemas, metadata objects, or behavior that does not exist yet.

## Event

Status: future. Depends on `Limiter` (`../limiter/ROADMAP.md`) and
the shared `Thread` / `Thread__c` service (`../thread-service/ROADMAP.md`
— Event work is expected to stay on the current `Thread__c`). Shares
`Async`'s Queueable thread model but is a **sibling framework**, not a subclass —
its payload model, table, and lack of priority make it look like a stripped-down
Async rather than an extension of it.

Event is the **stateful** answer to Async. Where Async refuses stateful payloads
and re-fetches records by Id inside `execute(Set<Id> ids)`, Event serializes the
payload itself and carries it through the work item. It should interrupt lower-
urgency Async work on the same thread when reliable publication is needed, while
preserving the straight-line processing model of the thread.

Event solves **two halves of the same coin** — reliable publish and reliable
consume — which is why it is separate from Async. Both halves address the same
Platform Event pain point: silent failures and the lack of built-in retry.

### Half 1 — Reliable publish

A limits-safe wrapper around `EventBus.publish()`. The caller hands Event a
payload; Event persists an `Event_Job__c` row and a Queueable performs the
actual `EventBus.publish()` only when `Limiter.isSafe()` allows. If limits
are exhausted, the work item moves to `Paused` instead of being dropped or
failing silently, and the framework auto-recovers (the Scheduler MVP1 monitor
re-checks and flips `Paused` back to pending).

### Half 2 — Reliable consume

Native Platform Event triggers fail silently and offer no retry. Event lets a
platform event trigger ingest its events with a single line — no trigger handler
class required (platform event triggers normally do not use one). Event
serializes the fired events into `Event_Job__c` and processes them async via the
Queueable chain, giving persistence, retry, and error visibility that native
platform events lack.

Map and JSON inputs skip the EventBus entirely and go straight to the
consume/process path.

### Public surface

Publish side:

- `Event.publish(List<SObject> events)` — platform events, deferred through a
  Queueable and published when limits allow.
- `Event.publish(List<Map<String, Object>> payloads)` — generic map payloads.
- `Event.publish(String json)` — JSON, normalized to a map.
- `Event.stage(...)` / `Event.flush()` — buffer work before committing, same
  staging pattern as `Async.stage` / `Async.flush`.

Consume side:

- `Event.ingest(List<SObject> events)` — the one-liner dropped into a platform
  event trigger body; serializes each event into an `Event_Job__c` process row.

Handler:

- `Event.Handler` — virtual base class. Subclasses override
  `execute(List<Generic> events)`. `Generic` (`../generic/AGENTS.md`) is the
  natural envelope since every stored payload is already a serialized map:
  handlers can read raw values by path, coerce primitives, or convert to a typed
  `SObject` (`(MyEvent__e) event.toSObject(MyEvent__e.sObjectType)`), and reuse
  `Generic`'s `mapping()` / `transform()` overrides. The signature stays
  `List<Generic>` regardless of batch size — a batch of one is a list of one —
  so performance tuning never changes the API.

### Rules and guards

- Guard `List<SObject>` usage so only platform events (API names containing
  `__e`) are accepted.
- Process events strictly FIFO. Do not introduce priority or reordering.
- Bundling may be supported, but only when explicitly enabled by configuration.
- Use async processing and finalizer tracking to avoid the silent-failure
  problem common with Platform Events.
- Consult `Limiter` before publishing events or starting event work.

### Schema

`Event_Job__c` — note there is no `Record_Id__c`; the payload travels with the
work item, split across four long-text fields so a single event can exceed one
field's storage limit:

| Field | Type | Purpose |
|---|---|---|
| `Apex__c` | Text(255) | Handler class name |
| `Job_Type__c` | Picklist | `Publish` \| `Process` |
| `Status__c` | Picklist | `Pending` \| `Running` \| `Paused` \| `Done` \| `Error` |
| `Thread__c` | Text(255) | Request thread id (same concept as `Async__c.Thread__c`) |
| `Payload1__c` | LongTextArea | Serialized JSON chunk 1 |
| `Payload2__c` | LongTextArea | Serialized JSON chunk 2 |
| `Payload3__c` | LongTextArea | Serialized JSON chunk 3 |
| `Payload4__c` | LongTextArea | Serialized JSON chunk 4 |
| `Error_Message__c` | LongTextArea | Truncated failure message |
| `Error_Stack_Trace__c` | LongTextArea | Truncated stack trace |

`Job_Type__c` carries the semantic difference between the publish path
(`Pending → Published`, where `Published` reuses the `Done` terminal state) and
the process path (`Pending → Running → Done`/`Error`), keeping the `Status__c`
picklist small.

`Event_Config__mdt`:

| Field | Type | Purpose |
|---|---|---|
| `Apex__c` | Text(255) | Handler class name (matches `Event_Job__c.Apex__c`) |
| `Batch_Size__c` | Number | Events processed per Queueable run |

### Open / not-yet-locked

- Whether `Paused` publish recovery shares the same `Limiter` resume
  monitor as Async or needs an Event-specific check (Event additionally watches
  available Platform Event publish allocation, not just Queueable depth).
- Exact `stage` / `flush` buffering signatures.
