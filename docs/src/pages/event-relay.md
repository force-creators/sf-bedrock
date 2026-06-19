---
layout: ../layouts/DocsLayout.astro
title: EventRelay | sf-bedrock docs
description: A durable event relay for Platform Event publication, inbound event processing, custom publishers, and tracked status.
eyebrow: Frameworks
heading: EventRelay
lede: EventRelay turns event publication and event processing into durable, tracked work. Bedrock stores Platform Event or generic payloads as Event__c rows, then ordered lanes drain them through publishers or handlers.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Configuration
    href: "#configuration"
  - label: Ingesting Work
    href: "#ingesting-work"
  - label: Publishing Work
    href: "#publishing-work"
  - label: Routes & Lanes
    href: "#routes--lanes"
  - label: Custom Handlers
    href: "#custom-handlers"
  - label: Custom Publishers
    href: "#custom-publishers"
  - label: Testing
    href: "#testing"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Notes & Edge Cases
    href: "#notes--edge-cases"
---

## Overview

`EventRelay` is Bedrock's durable event framework. It is for event work that
should survive the caller's transaction, keep visible status, preserve lane
order, and make success or failure inspectable.

The public model is intentionally small:

- **Start work:** call `EventRelay.publish(...)` with Platform Event SObjects,
  or generic payloads when the event should leave the org.
- **Ingest work:** call `EventRelay.ingest(...)` with Platform Event SObjects or
  generic payloads when the event should be processed by Apex.
- **Coordinate work:** call `EventRelay.stage(...)` and `EventRelay.flush()` when
  several services need to add publish-side Platform Events in one transaction.
- **Customize processing:** extend `EventRelay.Handler` and override
  `execute(List<SObject>)` or `execute(List<Generic>)`.
- **Customize publication:** extend `EventRelay.Publisher` and override
  `execute(List<SObject>)` or `execute(List<Generic>)`.
- **Keep lanes ordered:** route work into a stable lane key so each lane drains
  in FIFO order while other lanes can run separately.

Use `EventRelay` when event publication or consumption is important enough to
track. Common cases include Platform Events that represent integration handoffs,
durable webhook publication, and inbound event triggers that need retryable,
visible Apex processing instead of silent trigger failure.

Reach for direct `EventBus.publish(...)` instead when the publication is small,
non-critical, and does not need durable status, ordered lanes, or item-level
operational review. Reach for a normal Platform Event trigger when native
trigger behavior is enough and you do not need durable handler status.

## Quickstart

Using `EventRelay` for normal Platform Event publication is one call. Build
Platform Event SObjects, then publish them through the relay instead of calling
`EventBus.publish(...)` directly.

```apex
List<SObject> events = new List<SObject>{
    new Account_Changed__e(
        Account_Id__c = account.Id,
        Change_Type__c = 'HealthChanged'
    )
};

List<Id> workItemIds = EventRelay.publish(events);
```

The caller creates one `Event__c` work item for each event payload. EventRelay
stores the serialized payload, places it on a publish lane, and returns the new
work item Ids.

The built-in publisher later rehydrates those payloads back into Platform Event
SObjects and calls `EventBus.publish(...)` in a background transaction.

For inbound event processing, add a one-line trigger and a handler.

```apex
trigger AccountChangedTrigger on Account_Changed__e (after insert) {
    EventRelay.ingest(Trigger.new, AccountChangedHandler.class);
}
```

```apex
public with sharing class AccountChangedHandler extends EventRelay.Handler {
    public override void execute(List<SObject> records) {
        for (SObject record : records) {
            Id accountId = (Id) record.get('Account_Id__c');
            // Process the event payload.
        }
    }
}
```

The trigger stores process work and returns. The handler runs later, and each
selected work item becomes `Done` or `Error`.

## Examples

### Publish an account integration event

This service records an integration event without publishing it inline. The
service owns the business decision; EventRelay owns durable publication.

```apex
public with sharing class AccountIntegrationEventService {
    public List<Id> publishHealthChanged(List<Account> accounts) {
        List<SObject> events = new List<SObject>();

        for (Account account : accounts) {
            events.add(new Account_Health_Changed__e(
                Account_Id__c = account.Id,
                Health_Score__c = account.Health_Score__c
            ));
        }

        return EventRelay.publish(events);
    }
}
```

Each `Account_Health_Changed__e` becomes an `Event__c` row with `Job_Type__c =
'Publish'`, `Status__c = 'Pending'`, and a route-specific thread key. The
publication happens later when Thread starts the EventRelay publish pool.

### Stage several Platform Events before flushing

Use `stage` when separate services need to add Platform Events during the same
transaction. Use `flush` once at the orchestration boundary.

```apex
public with sharing class OrderEventService {
    public void stageSubmitted(Order__c order) {
        EventRelay.stage(new List<SObject>{
            new Order_Submitted__e(Order_Id__c = order.Id)
        });
    }

    public void stageFulfillmentRequested(Order__c order) {
        EventRelay.stage(new List<SObject>{
            new Fulfillment_Requested__e(Order_Id__c = order.Id)
        });
    }

    public List<Id> flushEvents() {
        return EventRelay.flush();
    }
}
```

Staging keeps the caller from scattering `Event__c` inserts across the
transaction. Nothing is persisted until `flush()` runs.

### Ingest Platform Events from a trigger

Use `ingest` when a Platform Event trigger should persist the payload and process
it later through a handler.

```apex
trigger OrderSubmittedTrigger on Order_Submitted__e (after insert) {
    EventRelay.ingest(Trigger.new, OrderSubmittedHandler.class);
}
```

```apex
public with sharing class OrderSubmittedHandler extends EventRelay.Handler {
    public override void execute(List<SObject> records) {
        Set<Id> orderIds = new Set<Id>();
        for (SObject record : records) {
            orderIds.add((Id) record.get('Order_Id__c'));
        }

        List<Order__c> orders = (List<Order__c>) Query.records([
            SELECT Id, Status__c
            FROM Order__c
            WHERE Id IN :orderIds
        ]);

        for (Order__c order : orders) {
            order.Status__c = 'Submitted';
        }

        DML.updateRecords(orders);
    }
}
```

The handler receives SObjects for Platform Event payloads. For generic payloads,
override `execute(List<Generic>)` instead.

### Publish through a custom SObject publisher

Pass a publisher type when Platform Event-shaped payloads should be delivered by
your own publisher instead of the built-in `EventBus.publish(...)` publisher.

```apex
public with sharing class WebhookEventPublisher extends EventRelay.Publisher {
    public override void execute(List<SObject> records) {
        for (SObject record : records) {
            try {
                sendWebhook(record);
            } catch (Exception error) {
                fail(record, error.getMessage());
            }
        }
    }

    void sendWebhook(SObject record) {
        // Build and send the callout in the shape your integration expects.
    }
}
```

```apex
EventRelay.publish(
    new List<SObject>{
        new Order_Submitted__e(Order_Id__c = order.Id)
    },
    WebhookEventPublisher.class
);
```

By default, every payload is treated as successful if `execute` completes. Call
`fail(record, message)` for individual records that should end in `Error`.

### Publish generic payloads

Generic payloads are for publishers that do not start from a Platform Event
SObject. They require routing because EventRelay needs to know which publisher
class and lane should receive the payload.

```apex
public with sharing class OrderWebhookPublisher extends EventRelay.Publisher {
    public override void execute(List<Generic> records) {
        for (Generic record : records) {
            String orderNumber = (String) record.get('orderNumber', String.class);
            if (String.isBlank(orderNumber)) {
                fail(record, 'Order number is required.');
                continue;
            }

            sendWebhook(record);
        }
    }

    void sendWebhook(Generic record) {
        // Build and send the callout from the Generic payload.
    }
}
```

```apex
EventRelay.publish(new List<Generic>{
    new Generic(new Map<String, Object>{
        'orderNumber' => '1001',
        'status' => 'Ready'
    })
});
```

Generic publishing requires an active `Event_Config__mdt` record whose
`Source_Type__c`, `Direction__c`, `Routing_Key__c`, and `Routing_Value__c`
match the payload.

### Idempotent Intake

Configure `Idempotency_Key_Path__c` on a route when repeated delivery should
create an audit row without running duplicate work. For Platform Event routes,
the value is a field API name. For `Generic` routes, the value is a `Generic`
path. Explicit class calls, such as `publish(events, MyPublisher.class)`, also
read the path when matching route metadata exists.

```apex
List<Id> workIds = EventRelay.publish(new List<SObject>{
    new Order_Submitted__e(
        Order_Number__c = '1001',
        Status__c = 'Ready'
    )
});
```

If EventRelay has already accepted or completed work for the same job type,
route, and key, the new `Event__c` row is inserted as `Stale` with an
explanatory message and is not enqueued.

## Configuration

Use `Event_Config__mdt` when EventRelay should resolve the publisher or handler
without an explicit Apex type. One config record defines one route.

For Platform Event ingestion, configure a route like this:

| Field | Value |
| --- | --- |
| `DeveloperName` | `OrderSubmittedIngest` |
| `Active__c` | `true` |
| `Direction__c` | `Ingest` |
| `Source_Type__c` | `PlatformEvent` |
| `Routing_Key__c` | `SObjectType` |
| `Routing_Value__c` | `Order_Submitted__e` |
| `Apex__c` | `OrderSubmittedHandler` |
| `Batch_Size__c` | `50` |

Then the trigger can rely on metadata routing:

```apex
trigger OrderSubmittedTrigger on Order_Submitted__e (after insert) {
    EventRelay.ingest(Trigger.new);
}
```

For generic payloads, `Routing_Key__c` is the key EventRelay reads from the
`Generic` payload, and `Routing_Value__c` is the value that selects the route.

```apex
EventRelay.ingest(new List<Generic>{
    new Generic(new Map<String, Object>{
        'EventType' => 'OrderSubmitted',
        'orderNumber' => '1001'
    })
});
```

That payload resolves to a config like this:

| Field | Value |
| --- | --- |
| `DeveloperName` | `OrderSubmittedGenericIngest` |
| `Direction__c` | `Ingest` |
| `Source_Type__c` | `Generic` |
| `Routing_Key__c` | `EventType` |
| `Routing_Value__c` | `OrderSubmitted` |
| `Apex__c` | `OrderSubmittedHandler` |

`DeveloperName` is the route and thread key for metadata-backed routes. Keep it
stable once work exists. `Batch_Size__c` overrides EventRelay's default batch
size for that route. `Max_Retries__c` caps framework-managed automatic retry for
failed publish and process work on that route. `Idempotency_Key_Path__c` enables
duplicate detection for the route.

## Ingesting Work

`ingest` is the direct entry point for events that should be processed by Apex.

```apex
List<Id> platformEventWork = EventRelay.ingest(platformEvents, OrderSubmittedHandler.class);
List<Id> genericWork = EventRelay.ingest(genericPayloads, OrderSubmittedHandler.class);
```

The Platform Event overload accepts only SObjects whose API names end in `__e`.
Each payload becomes an `Event__c` row with `Job_Type__c = 'Process'` on the
`EventRelayProcess` pool.

You can pass a handler explicitly:

```apex
EventRelay.ingest(Trigger.new, AccountChangedHandler.class);
```

The overloads without a handler type resolve active `Event_Config__mdt` records.
Platform Event routes match `Source_Type__c = 'PlatformEvent'`,
`Routing_Key__c = 'SObjectType'`, and `Routing_Value__c` equal to the Platform
Event API name. Generic routes match the configured key and value from the
payload.

## Publishing Work

`publish` is the direct entry point for work that should be created immediately.
It returns the Ids of the inserted `Event__c` rows.

```apex
List<Id> platformEventWork = EventRelay.publish(platformEvents);
List<Id> customPublisherWork = EventRelay.publish(platformEvents, WebhookEventPublisher.class);
List<Id> genericWork = EventRelay.publish(genericPayloads);
```

The Platform Event overload accepts only SObjects whose API names end in `__e`.
Passing ordinary records, such as `Account`, raises an error.

### Staging and flushing

`stage(List<SObject>)` buffers Platform Event SObjects in the current
transaction. `flush()` persists the buffered events and clears the buffer.

```apex
EventRelay.stage(new List<SObject>{ new Order_Submitted__e(Order_Id__c = order.Id) });
EventRelay.stage(new List<SObject>{ new Order_Audited__e(Order_Id__c = order.Id) });

List<Id> workItemIds = EventRelay.flush();
```

Calling `flush()` again after the buffer is empty returns an empty list.

## Routes & Lanes

Every `Event__c` work item records a route and a thread key.

The default publish-side Platform Event route uses the event API name for both
the route and payload type. For an `Account_Changed__e` payload, the lane key is:

```text
Publish:Account_Changed__e:Account_Changed__e
```

When an explicit publisher type is passed, the route includes the publisher
class name so the custom publisher gets its own lane:

```text
Account_Changed__e:AccountWebhookPublisher
Publish:Account_Changed__e:Account_Changed__e:AccountWebhookPublisher
```

Matching metadata can fan one payload out to several routes. In that case,
EventRelay creates one `Event__c` row per resolved route. Each row can have its
own publisher class and thread key.

Metadata-backed routes use the `Event_Config__mdt.DeveloperName` as both the
stored route and thread key. That keeps the lane stable without adding a
separate thread-key field to the config.

When an explicit handler type is passed to `ingest`, the process lane uses
`Process`, the payload type, and the handler route:

```text
Account_Changed__e:AccountChangedHandler
Process:Account_Changed__e:Account_Changed__e:AccountChangedHandler
```

![Subway-style roadmap map showing Event publication and Event consumption over shared Thread lanes.](/images/threading-event-subway.svg)

Thread keys are the ordering boundary. Work in one lane drains in FIFO order by
`CreatedDate`, `Order__c`, and `Name`. Separate lanes can move independently
when Thread has capacity.

### Strict contiguous batches

EventRelay only drains a contiguous batch that shares the same Apex class, route,
and payload type. If the next pending work item in a lane belongs to a different
publisher, handler, or route, the current batch stops before it.

That rule keeps one publisher or handler call focused on one coherent payload
shape while preserving the lane's order.

## Custom Handlers

Custom handlers extend `EventRelay.Handler`. Override the `execute` overload
that matches your payload shape.

```apex
public with sharing class ContactChangedHandler extends EventRelay.Handler {
    public override void execute(List<SObject> records) {
        Set<Id> contactIds = new Set<Id>();
        for (SObject record : records) {
            contactIds.add((Id) record.get('Contact_Id__c'));
        }

        processContacts(contactIds);
    }

    void processContacts(Set<Id> contactIds) {
        // Query once, then do bulk-safe work.
    }
}
```

```apex
public with sharing class OrderWebhookHandler extends EventRelay.Handler {
    public override void execute(List<Generic> records) {
        for (Generic record : records) {
            String orderNumber = (String) record.get('orderNumber', String.class);
            if (String.isBlank(orderNumber)) {
                fail(record, 'Order number is required.');
            }
        }
    }
}
```

If `execute` completes, EventRelay marks selected process work items `Done` by
default. A handler may call `complete(record)` or `fail(record, message)` for
individual records when it wants item-level results. Failed items follow the
route's `Max_Retries__c` cap: under the cap they return to `Pending` with
`Retry_Count__c` incremented; at the cap they become `Error`.

Platform Event handlers that already override `execute(List<Generic>)` continue
to work because the base SObject handler path can convert Platform Event records
to `Generic`. New handlers should prefer `execute(List<SObject>)` when they want
the Platform Event shape.

## Custom Publishers

Custom publishers extend `EventRelay.Publisher`. Override the `execute` overload
that matches your payload shape.

```apex
public with sharing class ContactWebhookPublisher extends EventRelay.Publisher {
    public override void execute(List<Generic> records) {
        for (Generic record : records) {
            if (String.isBlank((String) record.get('email', String.class))) {
                fail(record, 'Email is required.');
            }
        }
    }
}
```

Publisher results are item-level. If `execute` completes and no item is failed,
EventRelay marks every selected payload `Done`. Call `fail(record, message)` for
payloads that should end in `Error` or follow the route's retry cap. Use
`complete(record)` or `succeed(record)` only when a publisher first marked a
record failed and later needs to mark it successful again inside the same batch.

## Testing

Test subscriber logic directly. For handlers, construct the handler and call
the `execute` overload it owns with representative payloads. Mock the
collaborators your handler uses, then assert the business behavior it owns.

```apex
@istest
class OrderSubmittedHandlerTest {
    @istest static void execute_updatesSubmittedOrders() {
        OrderSubmittedHandler handler = new OrderSubmittedHandler();

        handler.execute(new List<SObject>{
            new Order_Submitted__e(Order_Id__c = 'a00000000000001AAA')
        });

        // Assert the DML or service behavior the handler owns.
    }
}
```

For custom publishers, keep transformation, validation, and delivery code in
small methods or collaborators that can be tested directly. In subscriber tests,
do not depend on EventRelay's internal payload/result classes. Bedrock's own
tests cover durable work creation, queue orchestration, item-level result
mapping, and background start behavior.

## How It Works

Three ideas explain the parts you need as a user.

**One: payloads become tracked work.** `publish` and `ingest` serialize each
payload into `Payload1__c` through `Payload4__c`, create one `Event__c` row per
resolved route, and store the Apex class, route, payload type, lane key, retry
count, and status.

**Two: lanes preserve order.** Creating work assigns each item to a lane. Work in
the same lane drains in order; separate lanes can drain independently when
capacity is available.

**Three: handlers and publishers write outcomes.** Publish work calls the
selected publisher. Ingest work calls the selected handler. Successful items
become `Done`; failed items become `Error` or return to `Pending` when
`Max_Retries__c` allows another attempt.

## Public API

> **A note on access modifiers.** In Apex, an omitted modifier means `private`.
> Members listed here are the intended app-facing surface. Treat other visible
> framework services and helpers as internal unless this page documents them.

### Static entry points

| Member | Signature | Description |
| --- | --- | --- |
| `publish` | `public static List<Id> publish(List<SObject> events)` | Creates durable publish work for Platform Event SObjects. Uses active `Event_Config__mdt` publish routes when they match; otherwise uses the built-in Platform Event publisher route. |
| `publish` | `public static List<Id> publish(List<SObject> events, Type publisherType)` | Creates durable publish work for Platform Event SObjects and routes it to the explicit publisher class. |
| `publish` | `public static List<Id> publish(List<Generic> payloads)` | Creates durable publish work for generic payloads. Requires an active matching `Event_Config__mdt` publish route. |
| `ingest` | `public static List<Id> ingest(List<SObject> events)` | Creates durable process work for Platform Event SObjects. Requires an active matching `Event_Config__mdt` ingest route. |
| `ingest` | `public static List<Id> ingest(List<SObject> events, Type handlerType)` | Creates durable process work for Platform Event SObjects and routes it to the explicit handler class. |
| `ingest` | `public static List<Id> ingest(List<Generic> payloads)` | Creates durable process work for generic payloads. Requires an active matching `Event_Config__mdt` ingest route. |
| `ingest` | `public static List<Id> ingest(List<Generic> payloads, Type handlerType)` | Creates durable process work for generic payloads and routes it to the explicit handler class. |
| `stage` | `public static void stage(List<SObject> events)` | Adds Platform Event SObjects to the current transaction buffer. |
| `flush` | `public static List<Id> flush()` | Persists buffered Platform Events and returns the new `Event__c` Ids. Returns an empty list when the buffer is empty. |

### Handler contract

| Member | Signature | Description |
| --- | --- | --- |
| `execute` | `public virtual void execute(List<SObject> records)` | Override this for Platform Event-shaped payloads. The base implementation converts records to `Generic` and calls `execute(List<Generic>)`, preserving existing Generic handlers. |
| `execute` | `public virtual void execute(List<Generic> records)` | Override this for generic payloads. The base implementation throws. |
| `complete` | `public void complete(SObject record)` | Marks one SObject payload successful in the current handler batch. Items are successful by default, so this is only needed after an earlier `fail`. |
| `complete` | `public void complete(Generic record)` | Marks one generic payload successful in the current handler batch. Items are successful by default, so this is only needed after an earlier `fail`. |
| `fail` | `public void fail(SObject record, String message)` | Marks one SObject payload failed in the current handler batch with a message. |
| `fail` | `public void fail(Generic record, String message)` | Marks one generic payload failed in the current handler batch with a message. |

### Publisher contract

| Member | Signature | Description |
| --- | --- | --- |
| `execute` | `public virtual void execute(List<SObject> records)` | Override this for Platform Event-shaped payloads. The base implementation throws. |
| `execute` | `public virtual void execute(List<Generic> records)` | Override this for generic payloads. The base implementation throws. |
| `complete` | `public void complete(SObject record)` | Marks one SObject payload successful in the current batch. |
| `complete` | `public void complete(Generic record)` | Marks one generic payload successful in the current batch. |
| `succeed` | `public void succeed(SObject record)` | Marks one SObject payload successful in the current batch. |
| `succeed` | `public void succeed(Generic record)` | Marks one generic payload successful in the current batch. |
| `fail` | `public void fail(SObject record, String message)` | Marks one SObject payload failed in the current batch with a message. |
| `fail` | `public void fail(Generic record, String message)` | Marks one generic payload failed in the current batch with a message. |

### Work metadata

| Artifact | Field | Purpose |
| --- | --- | --- |
| `Event__c` | `Apex__c` | Publisher or handler class name. Blank publish values use the built-in Platform Event publisher. |
| `Event__c` | `Job_Type__c` | `Publish` for outbound publication work or `Process` for inbound handler work. |
| `Event__c` | `Status__c` | Work state. Implemented statuses include `Pending`, `Running`, `Done`, `Stale`, and `Error`. |
| `Event__c` | `Route__c` | Route or destination key selected for the payload. |
| `Event__c` | `Payload_Type__c` | Platform Event API name or `Generic`. |
| `Event__c` | `Thread__c` | Lookup to the `Thread__c` lane that owns the work. |
| `Event__c` | `Thread_Key__c` | FIFO lane key. |
| `Event__c` | `Order__c` | Per-create-call ordering value used after `CreatedDate`. |
| `Event__c` | `Retry_Count__c` | Stored retry count. Automatic retry increments this value when a failed item is requeued below its configured cap. |
| `Event__c` | `Idempotency_Key__c` | Optional framework-derived logical work key. Duplicate accepted work for the same job type and route is inserted as `Stale`. |
| `Event__c` | `Payload1__c` - `Payload4__c` | Serialized payload chunks. Each chunk stores up to 32,768 characters. |
| `Event__c` | `Error_Message__c` | Publisher or handler error, stale duplicate reason, or runtime failure message. |
| `Event__c` | `Error_Stack_Trace__c` | Runtime failure stack trace when available. |

### Route metadata

| Artifact | Field | Purpose |
| --- | --- | --- |
| `Event_Config__mdt` | `DeveloperName` | Stable route name. Metadata-backed work stores this value in `Event__c.Route__c` and `Event__c.Thread_Key__c`. |
| `Event_Config__mdt` | `Active__c` | Enables the route when `true`. Inactive routes are ignored. |
| `Event_Config__mdt` | `Direction__c` | `Publish`, `Ingest`, or `Both`. |
| `Event_Config__mdt` | `Source_Type__c` | `PlatformEvent` or `Generic`. |
| `Event_Config__mdt` | `Routing_Key__c` | `SObjectType` for Platform Event routes; a payload key such as `EventType` for generic routes. |
| `Event_Config__mdt` | `Routing_Value__c` | Platform Event API name or generic payload value that selects the route. |
| `Event_Config__mdt` | `Apex__c` | Publisher class for publish routes or handler class for ingest routes. Platform Event publish routes may leave this blank to use the built-in publisher. |
| `Event_Config__mdt` | `Batch_Size__c` | Optional batch size override for this route. |
| `Event_Config__mdt` | `Max_Retries__c` | Optional automatic retry cap for failed publish and process work on this route. Blank or zero disables automatic retry. |
| `Event_Config__mdt` | `Idempotency_Key_Path__c` | Optional Platform Event field API name or `Generic` path used to derive `Event__c.Idempotency_Key__c` during intake. |

### Runtime defaults

| Setting | Value | Description |
| --- | --- | --- |
| Publish pool | `EventRelayPublish` | Thread pool used by EventRelay publication lanes. |
| Process pool | `EventRelayProcess` | Thread pool used by EventRelay process lanes. |
| Batch size | `50` | Default number of work items selected for one publish or process job when the route has no `Batch_Size__c`. |
| Limit threshold | `90` | Platform Event publish limit safety threshold used with `Limiter` for the built-in publisher. |

## Notes & Edge Cases

- **`publish` does not publish inline.** It records work. Publication runs
  later in a background transaction.
- **`ingest` does not process inline.** It records process work. Handler
  execution runs later in a background transaction.
- **Only Platform Event SObjects are accepted by the SObject overloads.** The
  API name must end in `__e`.
- **No-handler ingest requires config.** The no-handler `ingest` overloads throw
  when no active `Event_Config__mdt` record matches the payload.
- **Generic publishing needs config.** Generic payloads throw when no active
  `Event_Config__mdt` publish route matches the configured routing key/value.
- **Platform Event publication has a default route.** If no SObject routes are
  resolved, EventRelay uses the built-in Platform Event publisher route.
- **Payload storage is finite.** Serialized payloads are stored in four long text
  chunks. Payloads larger than that capacity throw an error.
- **Custom publishers are item-level.** If `execute` completes and no item is
  failed, every item is marked successful.
- **Custom handlers can be item-level.** If `execute` completes and no item is
  failed, every item is marked successful. Use `fail(record, message)` for the
  SObject or Generic records that should retry or become terminal errors.
- **Publisher result records must come from the current batch.** Calling
  `complete(...)`, `fail(...)`, or `succeed(...)` with another object instance
  throws.
- **Built-in Platform Event publishing checks limits.** When the Platform Event
  limit is not safe at the configured threshold, the owning `Thread__c` is
  marked `Paused` and the publish work remains `Pending`.
- **Idempotency is intake-only.** Duplicate idempotency keys create terminal
  `Stale` rows for audit. Stale rows do not run.
- **Strict contiguous batching can make smaller batches.** A lane may select
  fewer than the configured batch size when the next pending work item has a
  different publisher, handler, route, or payload type.
- **Automatic retry is route-configured.** `Max_Retries__c` greater than zero
  requeues failed work until the stored `Retry_Count__c` reaches the cap. Blank
  or zero leaves failures terminal.
