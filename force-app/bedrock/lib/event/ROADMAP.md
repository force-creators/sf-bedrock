# Event — Roadmap

A future Bedrock framework. This folder has no implemented code yet — it is
proposed work. Cross-cutting roadmap principles and feature sequencing live in
the repo root `ROADMAP.md`. Event should use the same `Thread__c` container as
Async so chained work remains linear and understandable.

The working architecture sketch lives in `DESIGN.md`.

These are intended designs, not finalized public APIs. Ask before locking
names, schemas, metadata objects, or behavior that does not exist yet.

## Event

Status: future. Depends on `Limiter` (`../limiter/ROADMAP.md`) and
the shared `Thread` / `Thread__c` service (`../thread-service/ROADMAP.md`
— Event work is expected to stay on the current `Thread__c`). Event should keep
the same thread lifecycle model that Async uses today: one live Queueable chain
per thread, finalizer-based continuation, thread handoff, and configurable
thread caps. It should **not** copy Async's dispatch policy wholesale. Event has
its own payload model, table, ordering rules, and no priority. It is a sibling
framework, not a subclass.

Adopted direction: treat `Thread__c` as the shared Bedrock lane/worker
primitive. Async is one consumer of `Thread__c`; Event and future threaded
frameworks should use the same primitive with their own `Pool__c` and
`Thread_Key__c` strategy instead of introducing a new lane-owner object per
framework.

Event is the **stateful** answer to Async. Where Async refuses stateful payloads
and re-fetches records by Id inside `execute(Set<Id> ids)`, Event serializes the
payload itself and carries it through the work item. It should interrupt lower-
urgency Async work on the same thread when reliable publication is needed, while
preserving the straight-line processing model of the thread.

Event solves **two halves of the same coin** — reliable publish and reliable
consume — which is why it is separate from Async. Both halves address the same
Platform Event pain point: silent failures and the lack of built-in retry.

### Current design decisions

- Reuse the shared `Thread__c` lifecycle model, but introduce a neutral thread
  runner / arbitration layer before Event is implemented. `Thread` should not
  permanently know how to dispatch only `Async__c` work.
- Event ordering is FIFO within a global lane, not within one originating
  transaction. Multiple synchronous transactions may append work to the same
  `Pool__c + Thread_Key__c` lane, but only one runner may process that lane at a
  time.
- Event has no priority. Cross-framework arbitration may allow publication work
  to run ahead of ordinary Async work on the same thread, but Event's internal
  queue remains ordered.
- Batching is on by default only when it is order-safe:
  `StrictContiguous` batching may collect adjacent compatible jobs from the head
  of a lane. Unordered same-handler batching is an explicit opt-in.
- Publication and consumption have different urgency. Reliable publication may
  interrupt Async; inbound consumption needs fairness so a firehose of incoming
  events does not starve ordinary Async work.
- Synchronous entrypoints can opportunistically start more than one thread
  runner. Platform Event triggers, REST endpoints, and other synchronous
  transactions may create work and then ask the thread runner to fill available
  capacity across Event and other threaded frameworks.
- Stale detection is intentionally not fully designed yet. The MVP should leave
  clear hooks for idempotency, TTL, partition keys, and publisher-provided
  sequence/version values without pretending timestamp-only ordering is a hard
  guarantee.

### Half 1 — Reliable publish

A limits-safe publication layer. The caller hands Event a payload; Event
persists an `Event_Job__c` row and a Queueable performs the actual publication
only when `Limiter.isSafe()` allows. If limits are exhausted, the work item
moves to `Paused` instead of being dropped or failing silently, and the
framework auto-recovers (the Scheduler MVP1 monitor re-checks and flips
`Paused` back to pending).

Platform Event publication through `EventBus.publish()` is the built-in
publisher. The framework should also allow custom publisher classes for
destinations such as REST endpoints, middleware, or external event buses. This
keeps reliable publication broader than Salesforce Platform Events without
forcing those integrations through Async.

### Half 2 — Reliable consume

Native Platform Event triggers fail silently and offer no retry. Event lets a
platform event trigger ingest its events with a single line — no trigger handler
class required (platform event triggers normally do not use one). Event
serializes the fired events into `Event_Job__c` and processes them async via the
Queueable chain, giving persistence, retry, and error visibility that native
platform events lack.

Salesforce allows Platform Event triggers to run as Automated Process or a
configured user. Other event sources may run as an integration user or a real
interactive user. Event should expose enough configuration levers that subscriber
orgs can choose sane thread and lane behavior for their own runtime users
instead of relying on a single hard-coded assumption.

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
- `Event.Publisher` — virtual base class for reliable publication destinations.
  The built-in Platform Event publisher uses `EventBus.publish()`. Subscriber
  orgs may provide custom publishers for REST, middleware, or other external
  destinations.

### Rules and guards

- Guard `List<SObject>` usage so only platform events (API names containing
  `__e`) are accepted.
- Process events FIFO within a lane. Do not introduce Event priority.
- Default batching should be `StrictContiguous`: collect only adjacent,
  compatible jobs from the head of the lane so batching does not reorder work.
- Unordered same-handler batching may be supported, but only when explicitly
  enabled by configuration.
- Use async processing and finalizer tracking to avoid the silent-failure
  problem common with Platform Events.
- Consult `Limiter` before publishing events or starting event work.
- Do not let Event consume work starve Async indefinitely. Cross-framework
  arbitration should distinguish urgent publication from ordinary inbound
  consumption.

### Routing

Routing should stay simple and deterministic for the first implementation.

- SObject payloads route by `SObjectType`.
- Generic payloads route through metadata using a discriminator path and value.
- If no route matches, the job should move to `Error`.
- If multiple routes match, the job should move to `Error` unless metadata
  provides an explicit tie-breaker.
- A future `Event.Router` override seam may support complex org-specific rules,
  but a rules engine is not part of the MVP.

### Ordering, lanes, and batching

Event needs a graceful lane model without turning the framework into a general
stream-processing engine. A lane is the scope where FIFO is protected. The
default lane for platform events can be event type / route, such as
`EventConsume:AccountChanged__e`; future configuration may partition by
destination, source, or business key when an org needs more parallelism.

Strict FIFO across the whole org would imply one global queue, which is simple
but too slow for the framework's default path. The intended model is more
practical: multiple lanes may run at the same time, but each lane is processed
in order.

Event lanes are global queues, not just per-transaction Async-style chains. If
two synchronous transactions both append `AccountChanged__e` work, they append
to the same `Thread__c` lane keyed by something like
`EventConsume:AccountChanged__e`. If that lane is already running, no second
runner starts for it. The append path and drain path must coordinate through the
same `Thread__c FOR UPDATE` lock.

`StrictContiguous` batching is the default performance path:

- Query the head job in a lane.
- Batch only immediately adjacent jobs that are compatible with that head job
  (same route / handler / publisher and same safe batching mode).
- Stop batching at the first incompatible job so later work never jumps the
  queue.

Unordered same-handler batching is an advanced opt-in for handlers and
publishers that explicitly do not care about event order.

### Synchronous greedy fan-out

Synchronous Event entrypoints can take advantage of Salesforce's higher
Queueable enqueue limit by starting multiple thread runners in one transaction.
This is especially useful for Platform Event triggers and REST/API ingestion:
the transaction can persist incoming work, then ask shared thread infrastructure
to start as many lanes as are currently safe.

This should live in the neutral thread runner / arbitration layer rather than
inside Event alone. The runner should decide how many threads to start by
combining:

- remaining Queueable enqueue capacity in the current transaction,
- configured per-user or per-source thread caps,
- `Limiter` safety checks,
- available pending lanes,
- cross-framework fairness between Event publication, Event consumption, Async,
  and future threaded frameworks.

Guardrails:

- Never start more than one runner for the same lane.
- Preserve FIFO inside each lane.
- Claim lane ownership with the same short-lock pattern used by `Thread__c`
  handoff. The same locked `Thread__c` record must protect both appending work
  and deciding that a lane is drained.
- Keep Queueable/finalizer continuation conservative; async contexts still
  chain one next runner at a time.
- Consider a framework setting such as `Max_Starts_Per_Transaction__c` so orgs
  can avoid consuming every available Queueable enqueue in one trigger or API
  request.

This makes the thread runner the pool manager: synchronous transactions can
greedily fill capacity, while Queueable chains continue to recycle capacity as
each thread drains.

### Stale and duplicate events

Stale detection remains open and should not be overbuilt before real use cases
shape it. The framework should still preserve the important hooks early:

- `Idempotency_Key__c` for duplicate protection when a publisher or source can
  provide a stable key.
- `Thread_Key__c` / partition key semantics for grouping events that describe
  the same business stream or destination.
- `Occurred_At__c` for payload event time.
- `Expires_At__c` or config-driven max age for TTL-style stale handling.
- `Sequence__c` or `Version__c` when the publisher can provide real ordering.

Timestamp-only ordering is best-effort, not a guarantee. Strong stale detection
requires a publisher-provided sequence/version or a business-state comparison in
the handler. A future handler context may expose these values so handlers can
decide whether to process, skip, or fail an event.

### Schema

`Event_Job__c` — note there is no `Record_Id__c`; the payload travels with the
work item, split across four long-text fields so a single event can exceed one
field's storage limit:

| Field | Type | Purpose |
|---|---|---|
| `Apex__c` | Text(255) | Handler class name |
| `Route__c` | Text(255) | Resolved handler, publisher, route, or destination key. |
| `Job_Type__c` | Picklist | `Publish` \| `Process` |
| `Status__c` | Picklist | `Pending` \| `Running` \| `Paused` \| `Done` \| `Error` |
| `Thread__c` | Lookup(Thread__c) | Thread that owns this event work item. |
| `Thread_Key__c` | Text(255) | Optional partition key used to preserve FIFO within a lane. |
| `Sequence__c` | Number | Optional source-provided ordering value. |
| `Idempotency_Key__c` | Text(255) | Optional source-provided duplicate detection key. |
| `Occurred_At__c` | DateTime | Time the source says the event occurred. |
| `Expires_At__c` | DateTime | Optional expiration time for TTL-style stale handling. |
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
| `Route__c` | Text(255) | Route/destination key for handler or publisher selection. |
| `Payload_Type__c` | Text(255) | SObject API name or generic discriminator value. |
| `Discriminator_Path__c` | Text(255) | JSON path used to route generic payloads. |
| `Batch_Size__c` | Number | Events processed per Queueable run. |
| `Batch_Mode__c` | Picklist | `StrictContiguous` by default; optional `UnorderedSameHandler`. |
| `Max_Age_Minutes__c` | Number | Optional TTL for stale detection. |

### Open / not-yet-locked

- Whether `Paused` publish recovery shares the same `Limiter` resume
  monitor as Async or needs an Event-specific check (Event additionally watches
  available Platform Event publish allocation, not just Queueable depth).
- Exact `stage` / `flush` buffering signatures.
- Exact neutral thread runner / arbitration API between Thread, Async, Event,
  and future threaded frameworks.
- Exact `Thread__c` keying and uniqueness strategy for `Pool__c +
  Thread_Key__c`.
- How much stale detection belongs in the framework versus handler-owned
  business logic.
