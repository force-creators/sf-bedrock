# Event — Design Sketch

This is a working sketch for the future `Event` framework. It is not an
implemented contract and should stay easy to revise. The goal is to put the
objects, classes, and data structures on the table before writing Apex or
metadata.

`Event` is a sibling framework to `Async`. It reuses the shared thread lifecycle
and finalizer model, but owns event payload storage, routing, ordering,
publication, consumption, batching, retry, and stale-event policy.

## Current Status

The concept fits Bedrock, and the shared thread/lane foundation now exists.
`ThreadRunner`, pool dispatchers, `Pool__c`, `Thread_Key__c`, and generated
lane uniqueness are implemented in the Thread service. Event itself is still
not implemented, so the next work should be a narrow build slice rather than a
full-framework pass.

- Async threads are transaction-born ordered chains.
- Event lanes are global ordered queues that many transactions may append to.
- A runner temporarily owns a lane while it drains work.
- The same lock must protect both appending work and deciding that a lane is
  drained.

Adopted direction: use `Thread__c` as the shared Bedrock lane/worker primitive,
not as an Async-only concept. Async uses one thread key per originating
transaction. Event uses durable global thread keys such as
`EventConsume:AccountChanged__e`. Future threaded frameworks should also plug
into `Thread__c` through their own pool/key strategy instead of creating a new
lane-owner object per framework.

The remaining planning work is to choose the first Event slice and lock only
the public API and schema needed for that slice. Treat Event as two halves over
shared storage and lanes: reliable publication and reliable consumption.

## Design Goals

- Make reliable event publication and reliable event consumption feel like one
  coherent framework.
- Preserve FIFO inside an explicit lane while still allowing safe concurrency
  across lanes.
- Batch by default without reordering work (`StrictContiguous`).
- Keep extension points simple enough for unmanaged subscriber orgs to adapt.
- Keep stale-event handling honest: provide hooks, do not pretend timestamps are
  a hard ordering guarantee.
- Share thread infrastructure with Async and future work pools without forcing
  Event into Async's record-Id payload model.

## Proposed Metadata Shape

These objects are intentionally sketched as fields and responsibilities rather
than actual Salesforce metadata files.

### `Thread__c`

Existing shared object. Adopt it as the generalized Bedrock lane/worker record.
This keeps one shared primitive for Async, Event, and future threaded pools.

| Field | Purpose |
|---|---|
| `Status__c` | Existing lifecycle: `Pending`, `Running`, `Done`. |
| `Pool__c` | Proposed owner pool: `Async`, `EventPublish`, `EventConsume`, future pools. |
| `Thread_Key__c` | Unique pool-specific lane key, such as `Async:<requestId>` or `EventConsume:AccountChanged__e`. |
| `Unique_Key__c` | Internal generated uniqueness key for `Pool__c + Thread_Key__c`. |
| `Origin_Request_Id__c` | Optional request id that created the thread/work. Useful for Async and synchronous Event entrypoints. |
| `Last_Started_At__c` | Optional operational visibility. |
| `Last_Drained_At__c` | Optional operational visibility. |

Rules:

- `Thread_Key__c` is the durable lane identity within a pool.
- Only one runner may own a `Pool__c + Thread_Key__c` lane at a time.
- The append path and the drain/close path must lock this same `Thread__c`
  record with `FOR UPDATE`.
- If Event work arrives while its lane is running, the transaction inserts new
  `Event_Job__c` rows and does not start another runner for that lane.
- If the runner is about to finish, it locks the thread/lane and checks for
  pending work again before marking the lane idle/done.

Examples:

| Pool | `Thread_Key__c` | Meaning |
|---|---|---|
| `Async` | `Async:<requestId>` | Transaction-born Async chain. |
| `EventConsume` | `EventConsume:AccountChanged__e` | Global consume lane for one platform event type. |
| `EventPublish` | `EventPublish:Webhook:OrderService` | Global publish lane for one destination route. |
| `DataApi` | `DataApi:AccountSync:ExternalSystemA` | Future threaded pool lane. |

Rejected-for-now alternative: a separate `Event_Lane__c` object would make
Event's global queue semantics very explicit, but it creates a new lane-owner
object for every future framework that needs ordered work. The adopted direction
keeps the shared abstraction in `Thread__c` and treats Async as the first
consumer, not the definition of the concept.

### `Event_Job__c`

Durable event work item. One row represents one logical event payload or
publication attempt.

| Field | Purpose |
|---|---|
| `Apex__c` | Handler or publisher class name selected by routing. |
| `Route__c` | Resolved route/destination key. |
| `Job_Type__c` | `Publish` or `Process`. |
| `Status__c` | `Pending`, `Running`, `Paused`, `Done`, `Skipped`, `Error`. |
| `Thread__c` | Lookup to the thread that owns this work item. |
| `Thread_Key__c` | FIFO boundary for this job, matching the owning `Thread__c.Thread_Key__c`. |
| `Order__c` | Framework-assigned ordering value inside a creation batch/lane. |
| `Sequence__c` | Optional source-provided ordering value. |
| `Idempotency_Key__c` | Optional duplicate detection key. |
| `Occurred_At__c` | Source event time. |
| `Expires_At__c` | Optional expiration time for TTL-style staleness. |
| `Retry_Count__c` | Framework retry count. |
| `Payload1__c` ... `Payload4__c` | Serialized JSON chunks. |
| `Error_Message__c` | Truncated terminal or latest error message. |
| `Error_Stack_Trace__c` | Truncated terminal or latest stack trace. |

Notes:

- `Skipped` is proposed so duplicate/stale events are visible without being
  reported as failures.
- `Order__c` is separate from `Sequence__c`. `Order__c` protects framework FIFO
  for rows created in the same transaction; `Sequence__c` represents a
  publisher/source guarantee when one exists.
- One platform event publish payload should normally be one `Event_Job__c` row
  so `Database.SaveResult` can map cleanly back to work-item status.

### `Event_Config__mdt`

Routing and processing configuration.

| Field | Purpose |
|---|---|
| `Route__c` | Stable route/destination key. |
| `Job_Type__c` | `Publish` or `Process`, if routes should be separated by direction. |
| `Payload_Type__c` | SObject API name or generic discriminator value. |
| `Discriminator_Path__c` | Generic JSON path used to identify the route. |
| `Apex__c` | Handler or publisher class name. |
| `Lane_Strategy__c` | Default lane key strategy, such as route, event type, source, or payload path. |
| `Lane_Path__c` | Optional Generic path used when the lane is derived from payload data. |
| `Batch_Size__c` | Maximum jobs per Queueable execution. |
| `Max_Retries__c` | Auto-retry cap for framework-managed retries. |
| `Max_Age_Minutes__c` | Optional TTL for stale handling. |
| `Active__c` | Allows routes to be disabled without deleting metadata. |

Open question: whether publish routes and consume routes should share one
metadata type or split later. One type is simpler for MVP; split types may be
clearer if publisher-specific fields grow.

### `Event_Settings__c`

Proposed hierarchical custom setting. Mirrors Async's configurable posture
without reusing Async-specific settings names.

| Field | Purpose |
|---|---|
| `Max_Threads__c` | Event-specific concurrency cap for the current running user/context. |
| `Max_Starts_Per_Transaction__c` | Greedy synchronous fan-out cap. |
| `Limits_Threshold_Pct__c` | Threshold passed to `Limiter`. |
| `Default_Batch_Size__c` | Fallback for routes with no batch size. |
| `Default_Max_Retries__c` | Fallback retry cap. |
| `Default_Max_Age_Minutes__c` | Optional fallback TTL. |
| `Track_Performance__c` | Future performance fields toggle. |

Open question: whether thread caps should live in a shared `Thread_Settings__c`
instead. Event likely needs Event-specific fan-out controls either way.

## Proposed Apex Surface

No code yet; this is only the shape of public and internal pieces.

Naming spike: a top-level Apex class named `Event` may collide with
Salesforce's standard `Event` SObject type. Verify this before locking the
public API name. If it conflicts, likely alternatives are `Events`,
`BedrockEvent`, or another short framework name that does not collide with
standard schema.

### `Event`

Static facade and Queueable base container.

Public entrypoints:

| Member | Purpose |
|---|---|
| `publish(List<SObject>)` | Reliable publish for platform event SObjects. |
| `publish(List<Generic>)` | Reliable publish for generic payloads routed to custom publishers. |
| `publish(String)` | Parse JSON and publish/process through generic routing. |
| `ingest(List<SObject>)` | Reliable consume from a platform event trigger. |
| `ingest(List<Generic>)` | Reliable consume for generic/API payloads. |
| `stage(...)` | Buffer work before committing. |
| `flush()` | Persist staged work and ask the runner to fill capacity. |

Static services:

| Service | Purpose |
|---|---|
| `Event.work` | Create, stage, flush, pause, run, complete, skip, fail, retry work items. |
| `Event.jobs` | Select the next event work, instantiate handler/publisher, attach finalizer. |
| `Event.routes` | Resolve payloads to route configs and lane keys. |
| `Event.payloads` | Serialize, chunk, rehydrate, and normalize payloads as `Generic`. |
| `Event.metadata` | Cache `Event_Config__mdt` reads. |
| `Event.settings` | Cache `Event_Settings__c` reads. |
| `Event.staleness` | Evaluate duplicate, TTL, and optional sequence/version decisions. |

### `Event.Handler`

Subscriber-owned consumption extension point.

Properties/contract:

| Member | Purpose |
|---|---|
| `execute(List<Generic>)` | Process one strict contiguous batch. |
| `context` | Optional future context with route, lane, job ids, source metadata, and stale hints. |

### `Event.Publisher`

Subscriber-owned publication extension point.

Properties/contract:

| Member | Purpose |
|---|---|
| `publish(List<Generic>)` | Publish one strict contiguous batch to its destination. |
| `context` | Optional future context with route, lane, job ids, and retry metadata. |
| `results` | Conceptual per-payload publication result collection. Needed because platform event publishing can partially succeed. |

Built-in publisher:

| Class | Purpose |
|---|---|
| `Event.PlatformEventPublisher` | Converts `Generic` payloads back to platform event SObjects and calls `EventBus.publish()`. |

### `Event.Route`

In-memory resolved route.

| Property | Purpose |
|---|---|
| `route` | Stable route key. |
| `jobType` | `Publish` or `Process`. |
| `apexClass` | Handler or publisher class name. |
| `payloadType` | SObject API name or generic discriminator value. |
| `batchSize` | Effective batch size after defaults. |
| `laneStrategy` | How to derive lane key. |
| `maxRetries` | Effective retry cap. |
| `maxAgeMinutes` | Effective TTL. |

### `Event.Envelope`

Normalized payload before persistence.

| Property | Purpose |
|---|---|
| `payload` | Payload as `Generic`. |
| `sourceSObjectType` | Present for platform event SObjects. |
| `route` | Resolved `Event.Route`. |
| `laneKey` | Derived FIFO lane. |
| `order` | Framework-assigned order in the creation batch. |
| `sequence` | Optional source-provided sequence/version. |
| `idempotencyKey` | Optional duplicate key. |
| `occurredAt` | Source event time. |
| `expiresAt` | Derived or source-provided expiration. |

### `Event.WorkItem`

In-memory representation of `Event_Job__c`.

| Property | Purpose |
|---|---|
| `id` | `Event_Job__c.Id`. |
| `threadId` | Owning `Thread__c.Id`. |
| `route` | Route key. |
| `apexClass` | Handler or publisher class. |
| `jobType` | `Publish` or `Process`. |
| `status` | Current status. |
| `laneKey` | FIFO lane. |
| `order` | Framework order. |
| `payload` | Rehydrated `Generic`. |
| `retryCount` | Current retry count. |

### `Event.Batch`

Dispatch batch selected from a lane.

| Property | Purpose |
|---|---|
| `threadId` | Owning thread. |
| `laneKey` | FIFO lane. |
| `route` | Shared route for strict contiguous batch. |
| `jobType` | `Publish` or `Process`. |
| `apexClass` | Handler or publisher class. |
| `workItemIds` | Work items included in execution. |
| `payloads` | `List<Generic>` passed to handler/publisher. |
| `batchMode` | Effective batching mode. |

### `Event.Result`

Per-work-item execution result.

| Property | Purpose |
|---|---|
| `workItemId` | Related `Event_Job__c`. |
| `status` | `Done`, `Skipped`, `Paused`, `Error`, or retry intent. |
| `message` | Optional message or error. |
| `stackTrace` | Optional stack trace. |
| `shouldRetry` | Whether framework retry should be attempted. |

## Thread Runner Integration

`ThreadRunner` is a proposed shared dispatcher, not Event-specific code.

Responsibilities:

- Claim pending lanes/threads safely.
- Start one runner per lane.
- In synchronous contexts, greedily start multiple safe lanes.
- In Queueable/finalizer contexts, continue conservatively.
- Ask pool-specific dispatchers what work exists and what should run next.
- Apply fairness between Event publication, Event consumption, Async, and
  future threaded pools.
- Prevent the stranded-work race where a runner decides a lane is empty while a
  synchronous transaction is appending new work.

For Event, `ThreadRunner` must treat `Thread_Key__c` as the global ordering
lock within the selected pool:

- Appending work locks the `Thread__c` lane record, inserts work, and starts a
  runner only if the lane is not already running.
- Draining work locks the same `Thread__c` lane record, checks pending work
  again, and only then marks the lane idle/done.
- If more work exists, the runner continues the lane or lets arbitration decide
  whether to yield for fairness.
- If no work exists, the lane is released and the runner may claim another lane
  or another pool's work.

Proposed data structures:

### `Thread.WorkPool`

| Property | Purpose |
|---|---|
| `pool` | `Async`, `EventPublish`, `EventConsume`, future pools. |
| `weight` | Fairness weighting. |
| `canInterrupt` | Whether work in this pool may run before lower-urgency pools. |

### `Thread.Claim`

| Property | Purpose |
|---|---|
| `threadId` | Claimed `Thread__c.Id`. |
| `pool` | Owning pool. |
| `threadKey` | Claimed lane key from `Thread__c.Thread_Key__c`. |
| `laneKey` | Optional readable partition key. |
| `failures` | Consecutive chain failures, reused from Async restart model. |

### `Thread.Dispatcher`

Conceptual interface each work pool provides to the runner.

| Member | Purpose |
|---|---|
| `hasPendingWork(Thread.Claim)` | Whether this pool has work for the claim. |
| `enqueueNext(Thread.Claim)` | Enqueue the next Queueable for the claim. |
| `complete(Thread.Claim)` | Mark claim/thread done when drained. |

Open question: Apex does not have interfaces with static members, so this may
be implemented as injectable services rather than a literal interface.

## End-to-End Flows

### Reliable Platform Event Publish

1. Caller invokes `Event.publish(List<SObject>)`.
2. `Event.work` validates `__e` SObject types.
3. `Event.routes` resolves the built-in Platform Event publisher route.
4. `Event.payloads` converts each event to `Generic`.
5. `Event.work` creates one `Event_Job__c` per payload with framework order.
6. `ThreadRunner` starts safe lanes. Synchronous callers may fill multiple
   lanes; async callers chain conservatively.
7. `Event.jobs` selects a strict contiguous batch from the lane.
8. `Event.PlatformEventPublisher` publishes the payloads.
9. `Event.jobs` maps per-payload `Database.SaveResult` values back to work-item
   results.
10. Finalizer updates each row and asks `ThreadRunner` to continue.

### Reliable Platform Event Consume

1. Platform Event trigger calls `Event.ingest(Trigger.new)`.
2. `Event.routes` resolves by SObject type.
3. `Event.payloads` converts each event to `Generic`.
4. `Event.work` creates one process job per event with lane and order.
5. `ThreadRunner` fills available capacity from the synchronous trigger
   transaction.
6. `Event.jobs` selects a strict contiguous batch.
7. Subscriber `Event.Handler` receives `List<Generic>`.
8. Finalizer marks rows `Done`, `Skipped`, retry, or `Error`.

### Reliable Generic/API Consume

1. REST/service code calls `Event.ingest(List<Generic>)` or `Event.ingest(json)`.
2. `Event.routes` resolves by discriminator path/value.
3. Lane key may come from route, source, or a configured payload path.
4. Work is persisted and processed through the same consume flow.

### Custom Publication

1. Caller invokes generic publish with a payload/destination route.
2. `Event.routes` resolves an `Event.Publisher` subclass.
3. Work is persisted as publish jobs.
4. The publisher runs a strict contiguous batch and returns per-work-item
   results.

## Current Holes To Discuss

- Apex naming: verify whether a top-level `Event` class can compile without
  colliding with the standard `Event` SObject type.
- Thread lifecycle language: docs and code need to explain that `Thread__c` is a
  Bedrock lane/worker primitive, not only an Async transaction chain.
- Thread uniqueness: determine how strongly `Pool__c + Thread_Key__c` must be
  enforced and whether a formula/external-id helper field is needed.
- Thread pool naming: `Pool__c` vs `Type__c`; likely `Pool__c` is clearer.
- Thread key: how much should be human-readable versus machine-derived?
- Event type as lane: good default for platform events, but probably not enough
  for orgs that need parallelism by business key.
- Strict contiguous SOQL: likely query the next N ordered jobs and stop in Apex
  at the first incompatible row.
- Same-transaction order: `CreatedDate` is not enough; `Order__c` or another
  framework sequence is probably needed.
- Partial publication: Platform Event publish results are per event. Publisher
  abstraction needs per-work-item results.
- Batch failures: handler exceptions fail the whole selected batch unless the
  handler/publisher returns per-item results.
- Stale detection: TTL and duplicate handling are straightforward; true
  out-of-sequence detection needs source sequence/version or business-state
  comparison.
- Payload retention: serialized event payloads may contain sensitive data and
  need archiving/deletion/masking guidance.
- Index/selectivity: status, thread, lane, route, job type, and order fields
  will become hot query filters.
- Fairness: publication can interrupt Async, but consumption should not starve
  Async forever.
- Manual retry: decide whether `Error -> Pending` preserves the old thread/lane
  or recomputes them.
