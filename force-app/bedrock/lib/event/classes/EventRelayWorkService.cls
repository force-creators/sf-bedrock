/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class EventRelayWorkService {
  @testVisible
  List<SObject> buffer = new List<SObject>();

  public virtual void stage(List<SObject> events) {
    if (events == null || events.isEmpty())
      return;

    buffer.addAll(events);
  }

  public virtual List<Id> flush() {
    if (buffer.isEmpty())
      return new List<Id>();

    List<SObject> events = new List<SObject>(buffer);
    buffer.clear();
    return create(events);
  }

  public virtual List<Id> create(List<SObject> events) {
    List<Event__c> workItems = newWorkItems(events, null);
    return create(workItems);
  }

  public virtual List<Id> create(List<SObject> events, Type publisherType) {
    List<Event__c> workItems = newWorkItems(events, publisherType);
    return create(workItems);
  }

  public virtual List<Id> create(List<Generic> genericPayloads) {
    List<Event__c> workItems = newWorkItems(genericPayloads);
    return create(workItems);
  }

  public virtual List<Id> createProcess(List<SObject> events) {
    List<Event__c> workItems = newProcessWorkItems(events, null);
    return create(workItems);
  }

  public virtual List<Id> createProcess(
    List<SObject> events,
    Type handlerType
  ) {
    List<Event__c> workItems = newProcessWorkItems(events, handlerType);
    return create(workItems);
  }

  public virtual List<Id> createProcess(List<Generic> genericPayloads) {
    List<Event__c> workItems = newProcessWorkItems(genericPayloads, null);
    return create(workItems);
  }

  public virtual List<Id> createProcess(
    List<Generic> genericPayloads,
    Type handlerType
  ) {
    List<Event__c> workItems = newProcessWorkItems(
      genericPayloads,
      handlerType
    );
    return create(workItems);
  }

  public virtual List<Id> create(List<Event__c> workItems) {
    if (workItems.isEmpty())
      return new List<Id>();

    markStaleWork(workItems);
    DML.insertRecords(workItems);
    List<Event__c> runnableWorkItems = runnableWorkItems(workItems);
    Thread.reopen(threadIdsFrom(runnableWorkItems));
    EventRelay.jobs.enqueue(runnableWorkItems);
    return idsFrom(workItems);
  }

  public virtual List<Event__c> newWorkItems(
    List<SObject> events,
    Type publisherType
  ) {
    List<Event__c> workItems = new List<Event__c>();
    if (events == null || events.isEmpty())
      return workItems;

    Integer order = 0;
    for (SObject eventRecord : events) {
      String eventType = eventType(eventRecord);
      for (EventRelay.Route route : sObjectRoutes(eventType, publisherType)) {
        Id threadId = Thread.currentOrCreate(
          EventRelay.consts.PUBLISH_POOL,
          route.threadKey
        );
        Event__c workItem = newWorkItem(
          route,
          EventRelay.consts.PUBLISH,
          route.payloadType,
          threadId,
          order
        );
        workItem.Idempotency_Key__c = idempotencyKey(eventRecord, route);
        EventRelay.payloads.write(
          workItem,
          EventRelay.payloads.serialize(eventRecord)
        );
        workItems.add(workItem);
        order++;
      }
    }
    return workItems;
  }

  public virtual List<Event__c> newWorkItems(List<Generic> genericPayloads) {
    List<Event__c> workItems = new List<Event__c>();
    if (genericPayloads == null || genericPayloads.isEmpty())
      return workItems;

    Integer order = 0;
    for (Generic payload : genericPayloads) {
      if (payload == null) {
        throw new EventRelay.EventRelayException(
          'EventRelay.publish requires non-null generic payloads.'
        );
      }

      List<EventRelay.Route> resolvedRoutes = EventRelay.routes.forGeneric(
        payload,
        EventRelay.consts.PUBLISH
      );
      if (resolvedRoutes == null || resolvedRoutes.isEmpty()) {
        throw new EventRelay.EventRelayException(
          'EventRelay.publish requires route metadata for generic payloads.'
        );
      }

      for (EventRelay.Route route : resolvedRoutes) {
        Id threadId = Thread.currentOrCreate(
          EventRelay.consts.PUBLISH_POOL,
          route.threadKey
        );
        Event__c workItem = newWorkItem(
          route,
          EventRelay.consts.PUBLISH,
          EventRelay.consts.GENERIC_PAYLOAD,
          threadId,
          order
        );
        workItem.Idempotency_Key__c = idempotencyKey(payload, route);
        EventRelay.payloads.write(workItem, payload.json());
        workItems.add(workItem);
        order++;
      }
    }
    return workItems;
  }

  public virtual List<Event__c> newProcessWorkItems(
    List<SObject> events,
    Type handlerType
  ) {
    List<Event__c> workItems = new List<Event__c>();
    if (events == null || events.isEmpty())
      return workItems;

    Integer order = 0;
    for (SObject eventRecord : events) {
      String eventType = eventType(eventRecord);
      for (
        EventRelay.Route route : sObjectProcessRoutes(eventType, handlerType)
      ) {
        Id threadId = Thread.currentOrCreate(
          EventRelay.consts.PROCESS_POOL,
          route.threadKey
        );
        Event__c workItem = newWorkItem(
          route,
          EventRelay.consts.PROCESS,
          route.payloadType,
          threadId,
          order
        );
        workItem.Idempotency_Key__c = idempotencyKey(eventRecord, route);
        EventRelay.payloads.write(
          workItem,
          EventRelay.payloads.serialize(eventRecord)
        );
        workItems.add(workItem);
        order++;
      }
    }
    return workItems;
  }

  public virtual List<Event__c> newProcessWorkItems(
    List<Generic> genericPayloads,
    Type handlerType
  ) {
    List<Event__c> workItems = new List<Event__c>();
    if (genericPayloads == null || genericPayloads.isEmpty())
      return workItems;

    Integer order = 0;
    for (Generic payload : genericPayloads) {
      if (payload == null) {
        throw new EventRelay.EventRelayException(
          'EventRelay.ingest requires non-null generic payloads.'
        );
      }

      for (
        EventRelay.Route route : genericProcessRoutes(payload, handlerType)
      ) {
        Id threadId = Thread.currentOrCreate(
          EventRelay.consts.PROCESS_POOL,
          route.threadKey
        );
        Event__c workItem = newWorkItem(
          route,
          EventRelay.consts.PROCESS,
          EventRelay.consts.GENERIC_PAYLOAD,
          threadId,
          order
        );
        workItem.Idempotency_Key__c = idempotencyKey(payload, route);
        EventRelay.payloads.write(workItem, payload.json());
        workItems.add(workItem);
        order++;
      }
    }
    return workItems;
  }

  Event__c newWorkItem(
    EventRelay.Route route,
    String jobType,
    String payloadType,
    Id threadId,
    Integer order
  ) {
    return new Event__c(
      Apex__c = route.apexClass,
      Job_Type__c = jobType,
      Status__c = EventRelay.consts.PENDING,
      Route__c = route.route,
      Payload_Type__c = payloadType,
      Thread__c = threadId,
      Thread_Key__c = route.threadKey,
      Order__c = order,
      Retry_Count__c = 0
    );
  }

  void markStaleWork(List<Event__c> workItems) {
    Map<String, Event__c> acceptedWorkByKey = EventRelay.queries.getAcceptedWorkByIdempotencyKey(
      workItems
    );
    for (Event__c workItem : workItems) {
      if (String.isBlank(workItem.Idempotency_Key__c))
        continue;

      String lookupKey = idempotencyLookupKey(workItem);
      if (acceptedWorkByKey.containsKey(lookupKey)) {
        markStale(workItem, acceptedWorkByKey.get(lookupKey));
        continue;
      }
      acceptedWorkByKey.put(lookupKey, workItem);
    }
  }

  void markStale(Event__c workItem, Event__c acceptedWork) {
    workItem.Status__c = EventRelay.consts.STALE;
    workItem.Error_Message__c = acceptedWork.Id == null
      ? 'Duplicate idempotency key already accepted in this transaction.'
      : 'Duplicate idempotency key already accepted by Event work item ' +
        acceptedWork.Id +
        '.';
  }

  List<Event__c> runnableWorkItems(List<Event__c> workItems) {
    List<Event__c> runnable = new List<Event__c>();
    for (Event__c workItem : workItems) {
      if (workItem.Status__c == EventRelay.consts.PENDING)
        runnable.add(workItem);
    }
    return runnable;
  }

  String idempotencyKey(SObject eventRecord, EventRelay.Route route) {
    if (route == null || String.isBlank(route.idempotencyKeyPath))
      return null;

    String fieldName = route.idempotencyKeyPath.trim();
    try {
      return normalizedIdempotencyKey(eventRecord.get(fieldName));
    } catch (Exception e) {
      throw new EventRelay.EventRelayException(
        'Event route ' +
          route.route +
          ' has invalid idempotency key field ' +
          fieldName +
          '.'
      );
    }
  }

  String idempotencyKey(Generic payload, EventRelay.Route route) {
    if (route == null || String.isBlank(route.idempotencyKeyPath))
      return null;

    return normalizedIdempotencyKey(
      payload.get(route.idempotencyKeyPath.trim(), String.class)
    );
  }

  String normalizedIdempotencyKey(Object value) {
    if (value == null)
      return null;

    String key = String.valueOf(value).trim();
    if (String.isBlank(key))
      return null;
    if (key.length() > 255) {
      throw new EventRelay.EventRelayException(
        'EventRelay idempotency keys must be 255 characters or fewer.'
      );
    }
    return key;
  }

  public virtual void running(Set<Id> workItemIds) {
    updateStatus(
      workItemIds,
      new Event__c(Status__c = EventRelay.consts.RUNNING)
    );
  }

  public virtual void complete(Set<Id> workItemIds) {
    updateStatus(workItemIds, new Event__c(Status__c = EventRelay.consts.DONE));
  }

  public virtual List<Id> retry(Set<Id> workItemIds) {
    List<Event__c> workItems = EventRelay.queries.getRetryableWorkItems(
      workItemIds
    );
    if (workItems.isEmpty())
      return new List<Id>();

    List<SObject> updates = new List<SObject>();
    for (Event__c workItem : workItems) {
      Event__c updateRecord = new Event__c(
        Id = workItem.Id,
        Status__c = EventRelay.consts.PENDING
      );
      updateRecord.Error_Message__c = null;
      updateRecord.Error_Stack_Trace__c = null;
      updates.add(updateRecord);
    }
    DML.updateRecords(updates);
    Thread.reopen(threadIdsFrom(workItems));
    EventRelay.jobs.enqueue(workItems);
    return idsFrom(workItems);
  }

  public virtual void fail(
    Set<Id> workItemIds,
    String message,
    String stackTrace
  ) {
    applyFailure(
      EventRelay.queries.getWorkItemsById(workItemIds),
      new EventRelay.PublishResult(false, message),
      stackTrace
    );
  }

  public virtual void applyResults(
    List<Event__c> workItems,
    List<EventRelay.PublishResult> results
  ) {
    if (workItems == null || workItems.isEmpty())
      return;

    List<SObject> updates = new List<SObject>();
    List<EventRelay.PublishResult> safeResults = results == null
      ? new List<EventRelay.PublishResult>()
      : results;
    for (Integer i = 0; i < workItems.size(); i++) {
      EventRelay.PublishResult result = i < safeResults.size()
        ? safeResults[i]
        : new EventRelay.PublishResult(
            false,
            'Publisher returned no result for work item ' + workItems[i].Id
          );

      updates.add(
        result.success
          ? successUpdate(workItems[i])
          : failureUpdate(workItems[i], result, null)
      );
    }
    DML.updateRecords(updates);
  }

  public virtual void applyProcessResults(
    List<Event__c> workItems,
    List<EventRelay.ProcessResult> results
  ) {
    if (workItems == null || workItems.isEmpty())
      return;

    List<SObject> updates = new List<SObject>();
    List<EventRelay.ProcessResult> safeResults = results == null
      ? new List<EventRelay.ProcessResult>()
      : results;
    for (Integer i = 0; i < workItems.size(); i++) {
      EventRelay.ProcessResult result = i < safeResults.size()
        ? safeResults[i]
        : new EventRelay.ProcessResult(
            EventRelay.consts.ERROR,
            'Handler returned no result for work item ' + workItems[i].Id
          );

      updates.add(processUpdate(workItems[i], result));
    }
    DML.updateRecords(updates);
  }

  void applyFailure(
    List<Event__c> workItems,
    EventRelay.PublishResult result,
    String stackTrace
  ) {
    if (workItems == null || workItems.isEmpty())
      return;

    List<SObject> updates = new List<SObject>();
    for (Event__c workItem : workItems) {
      updates.add(failureUpdate(workItem, result, stackTrace));
    }
    DML.updateRecords(updates);
  }

  Event__c successUpdate(Event__c workItem) {
    return new Event__c(Id = workItem.Id, Status__c = EventRelay.consts.DONE);
  }

  Event__c processUpdate(Event__c workItem, EventRelay.ProcessResult result) {
    if (result.status == EventRelay.consts.DONE)
      return successUpdate(workItem);
    return failureUpdate(
      workItem,
      new EventRelay.PublishResult(false, result.message),
      null
    );
  }

  Event__c failureUpdate(
    Event__c workItem,
    EventRelay.PublishResult result,
    String stackTrace
  ) {
    Integer retryCount = retryCount(workItem);
    Boolean shouldRetry =
      retryCount < EventRelay.metadata.maxRetries(workItem.Route__c);
    Event__c updateRecord = new Event__c(
      Id = workItem.Id,
      Status__c = shouldRetry
        ? EventRelay.consts.PENDING
        : EventRelay.consts.ERROR,
      Error_Message__c = truncate(result.message),
      Error_Stack_Trace__c = truncate(stackTrace)
    );
    if (shouldRetry)
      updateRecord.Retry_Count__c = retryCount + 1;
    return updateRecord;
  }

  Integer retryCount(Event__c workItem) {
    if (
      workItem == null ||
      workItem.Retry_Count__c == null ||
      workItem.Retry_Count__c < 0
    )
      return 0;
    return workItem.Retry_Count__c.intValue();
  }

  public virtual void prepareRecovery(Id threadId) {
    prepareRecovery(threadId, EventRelay.consts.PUBLISH);
  }

  public virtual void prepareRecovery(Id threadId, String jobType) {
    updateStatus(
      EventRelay.queries.getRunningWorkItemIds(threadId, jobType),
      new Event__c(Status__c = EventRelay.consts.PENDING)
    );
  }

  void updateStatus(Set<Id> workItemIds, Event__c values) {
    if (workItemIds == null || workItemIds.isEmpty())
      return;

    List<SObject> updates = new List<SObject>();
    for (Id workItemId : workItemIds) {
      Event__c updateRecord = new Event__c(Id = workItemId);
      if (values.Status__c != null)
        updateRecord.Status__c = values.Status__c;
      if (values.Error_Message__c != null)
        updateRecord.Error_Message__c = values.Error_Message__c;
      if (values.Error_Stack_Trace__c != null)
        updateRecord.Error_Stack_Trace__c = values.Error_Stack_Trace__c;
      updates.add(updateRecord);
    }
    DML.updateRecords(updates);
  }

  List<Id> idsFrom(List<Event__c> workItems) {
    List<Id> ids = new List<Id>();
    for (Event__c workItem : workItems) {
      if (workItem.Id != null)
        ids.add(workItem.Id);
    }
    return ids;
  }

  Set<Id> threadIdsFrom(List<Event__c> workItems) {
    Set<Id> threadIds = new Set<Id>();
    for (Event__c workItem : workItems) {
      if (workItem.Thread__c != null)
        threadIds.add(workItem.Thread__c);
    }
    return threadIds;
  }

  String eventType(SObject eventRecord) {
    if (eventRecord == null) {
      throw new EventRelay.EventRelayException(
        'EventRelay requires platform event records.'
      );
    }

    String eventType = eventRecord.getSObjectType().getDescribe().getName();
    if (!eventType.endsWith('__e')) {
      throw new EventRelay.EventRelayException(
        'EventRelay only accepts platform event SObjects.'
      );
    }
    return eventType;
  }

  String publisherClass(Type publisherType) {
    if (publisherType == null) {
      throw new EventRelay.EventRelayException(
        'EventRelay.publish requires a publisher class for custom publishers.'
      );
    }
    return publisherType.getName();
  }

  List<EventRelay.Route> sObjectRoutes(String eventType, Type publisherType) {
    if (publisherType != null) {
      String route = eventType + ':' + publisherType.getName();
      String publisher = publisherClass(publisherType);
      return new List<EventRelay.Route>{
        new EventRelay.Route(
          route,
          publisher,
          eventType,
          routeThreadKey(EventRelay.consts.PUBLISH, eventType, route),
          EventRelay.routes.idempotencyKeyPathForSObject(
            eventType,
            EventRelay.consts.PUBLISH,
            publisher
          )
        )
      };
    }

    List<EventRelay.Route> resolvedRoutes = EventRelay.routes.forSObject(
      eventType,
      EventRelay.consts.PUBLISH
    );
    return resolvedRoutes == null || resolvedRoutes.isEmpty()
      ? new List<EventRelay.Route>{ defaultPlatformEventRoute(eventType) }
      : resolvedRoutes;
  }

  List<EventRelay.Route> sObjectProcessRoutes(
    String eventType,
    Type handlerType
  ) {
    if (handlerType != null) {
      String route = eventType + ':' + handlerType.getName();
      String handler = handlerClass(handlerType);
      return new List<EventRelay.Route>{
        new EventRelay.Route(
          route,
          handler,
          eventType,
          routeThreadKey(EventRelay.consts.PROCESS, eventType, route),
          EventRelay.routes.idempotencyKeyPathForSObject(
            eventType,
            EventRelay.consts.INGEST,
            handler
          )
        )
      };
    }

    List<EventRelay.Route> resolvedRoutes = EventRelay.routes.forSObject(
      eventType,
      EventRelay.consts.INGEST
    );
    if (resolvedRoutes == null || resolvedRoutes.isEmpty()) {
      throw new EventRelay.EventRelayException(
        'EventRelay.ingest requires route metadata or an explicit handler class.'
      );
    }
    return resolvedRoutes;
  }

  List<EventRelay.Route> genericProcessRoutes(
    Generic payload,
    Type handlerType
  ) {
    if (handlerType != null) {
      String route =
        EventRelay.consts.GENERIC_PAYLOAD +
        ':' +
        handlerType.getName();
      String handler = handlerClass(handlerType);
      return new List<EventRelay.Route>{
        new EventRelay.Route(
          route,
          handler,
          EventRelay.consts.GENERIC_PAYLOAD,
          routeThreadKey(
            EventRelay.consts.PROCESS,
            EventRelay.consts.GENERIC_PAYLOAD,
            route
          ),
          EventRelay.routes.idempotencyKeyPathForGeneric(
            payload,
            EventRelay.consts.INGEST,
            handler
          )
        )
      };
    }

    List<EventRelay.Route> resolvedRoutes = EventRelay.routes.forGeneric(
      payload,
      EventRelay.consts.INGEST
    );
    if (resolvedRoutes == null || resolvedRoutes.isEmpty()) {
      throw new EventRelay.EventRelayException(
        'EventRelay.ingest requires route metadata or an explicit handler class.'
      );
    }
    return resolvedRoutes;
  }

  EventRelay.Route defaultPlatformEventRoute(String payloadType) {
    return new EventRelay.Route(
      payloadType,
      EventRelay.consts.PLATFORM_EVENT_PUBLISHER,
      payloadType,
      routeThreadKey(EventRelay.consts.PUBLISH, payloadType, payloadType)
    );
  }

  String routeThreadKey(String jobType, String payloadType, String route) {
    return String.join(
      new List<String>{
        String.isBlank(jobType) ? EventRelay.consts.PUBLISH : jobType.trim(),
        String.isBlank(payloadType)
          ? EventRelay.consts.GENERIC_PAYLOAD
          : payloadType.trim(),
        String.isBlank(route) ? 'Default' : route.trim()
      },
      ':'
    );
  }

  String handlerClass(Type handlerType) {
    if (handlerType == null) {
      throw new EventRelay.EventRelayException(
        'EventRelay.ingest requires a handler class.'
      );
    }
    return handlerType.getName();
  }

  String truncate(String value) {
    if (value == null || value.length() <= 32768)
      return value;

    return value.substring(0, 32768);
  }

  String idempotencyLookupKey(Event__c workItem) {
    return JSON.serialize(
      new List<String>{
        workItem.Job_Type__c,
        workItem.Route__c,
        workItem.Idempotency_Key__c
      }
    );
  }
}
