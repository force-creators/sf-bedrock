/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class EventRelay {
  public static Constants consts = new Constants();
  public static JobService jobs = new JobService();
  public static WorkService work = new WorkService();
  public static QueryService queries = new QueryService();
  public static PayloadService payloads = new PayloadService();
  public static HandlerService handlers = new HandlerService();
  public static PublisherService publishers = new PublisherService();
  public static MetadataService metadata = new MetadataService();
  public static RouteService routes = new RouteService();
  public static SettingsService settings = new SettingsService();
  public static WakeService wakeSignal = new WakeService();

  @testVisible
  static void reset() {
    jobs = new JobService();
    work = new WorkService();
    queries = new QueryService();
    payloads = new PayloadService();
    handlers = new HandlerService();
    publishers = new PublisherService();
    metadata = new MetadataService();
    routes = new RouteService();
    settings = new SettingsService();
    wakeSignal = new WakeService();
    Thread.reset();
  }

  public virtual with sharing class Constants {
    public String PUBLISH_POOL = 'EventRelayPublish';
    public String PROCESS_POOL = 'EventRelayProcess';
    public String PLATFORM_EVENT_PUBLISHER = PlatformEventPublisher.class
      .getName();
    public String GENERIC_PAYLOAD = 'Generic';
    public String PLATFORM_EVENT = 'PlatformEvent';
    public String BOTH = 'Both';
    public String ROUTING_KEY_SOBJECT_TYPE = 'SObjectType';
    public String INGEST = 'Ingest';
    public String PUBLISH = 'Publish';
    public String PROCESS = 'Process';
    public String PENDING = 'Pending';
    public String RUNNING = 'Running';
    public String STALE = 'Stale';
    public String DONE = 'Done';
    public String ERROR = 'Error';
  }

  public static List<Id> publish(List<SObject> events) {
    return work.create(events);
  }

  public static List<Id> publish(List<SObject> events, Type publisherType) {
    return work.create(events, publisherType);
  }

  public static List<Id> publish(List<Generic> payloads) {
    return work.create(payloads);
  }

  public static List<Id> ingest(List<SObject> events) {
    return work.createProcess(events);
  }

  public static List<Id> ingest(List<SObject> events, Type handlerType) {
    return work.createProcess(events, handlerType);
  }

  public static List<Id> ingest(List<Generic> payloads) {
    return work.createProcess(payloads);
  }

  public static List<Id> ingest(List<Generic> payloads, Type handlerType) {
    return work.createProcess(payloads, handlerType);
  }

  public static List<Id> retry(Set<Id> workItemIds) {
    return work.retry(workItemIds);
  }

  public static void wake() {
    if (
      !Thread.service.canEnqueue() ||
      Thread.service.hasEnqueued ||
      System.isQueueable() ||
      Thread.service.isFinalizer
    )
      return;

    Thread.service.fillAvailableSlots(consts.PUBLISH_POOL);
    Thread.service.fillAvailableSlots(consts.PROCESS_POOL);
  }

  public static void stage(List<SObject> events) {
    work.stage(events);
  }

  public static List<Id> flush() {
    return work.flush();
  }

  public static Boolean isEventPool(String pool) {
    String normalizedPool = String.isBlank(pool) ? '' : pool.trim();
    return normalizedPool == consts.PUBLISH_POOL ||
      normalizedPool == consts.PROCESS_POOL;
  }

  public virtual with sharing class WorkService extends EventRelayWorkService {
  }

  public virtual with sharing class JobService extends EventRelayJobService {
  }

  public virtual with sharing class QueryService extends EventRelayQueryService {
  }

  public virtual with sharing class PayloadService extends EventRelayPayloadService {
  }

  public virtual with sharing class Handler {
    List<ProcessResult> results = new List<ProcessResult>();
    List<SObject> currentSObjectRecords = new List<SObject>();
    List<Generic> currentGenericRecords = new List<Generic>();

    public virtual List<ProcessResult> process(List<Event__c> workItems) {
      try {
        if (isGeneric(workItems)) {
          currentGenericRecords = payloads.toGenericEvents(workItems);
          results = successProcessResults(currentGenericRecords.size());
          execute(currentGenericRecords);
        } else {
          currentSObjectRecords = payloads.toSObjects(workItems);
          results = successProcessResults(currentSObjectRecords.size());
          execute(currentSObjectRecords);
        }
        return new List<ProcessResult>(results);
      } finally {
        reset();
      }
    }

    public virtual List<ProcessResult> process(List<Generic> records) {
      try {
        currentGenericRecords = records == null ? new List<Generic>() : records;
        results = successProcessResults(currentGenericRecords.size());
        execute(currentGenericRecords);
        return new List<ProcessResult>(results);
      } finally {
        reset();
      }
    }

    public virtual void execute(List<SObject> records) {
      currentGenericRecords = toGenericRecords(records);
      execute(currentGenericRecords);
    }

    public virtual void execute(List<Generic> records) {
      throw new EventRelayException(
        'Handler does not support generic payloads.'
      );
    }

    public void complete(SObject record) {
      mark(indexOf(record), consts.DONE, null);
    }

    public void complete(Generic record) {
      mark(indexOf(record), consts.DONE, null);
    }

    public void fail(SObject record, String message) {
      mark(indexOf(record), consts.ERROR, message);
    }

    public void fail(Generic record, String message) {
      mark(indexOf(record), consts.ERROR, message);
    }

    void mark(Integer index, String status, String message) {
      if (index == null || index < 0 || index >= results.size()) {
        throw new EventRelayException(
          'Handler result item is not part of the current batch.'
        );
      }
      results[index] = new ProcessResult(status, message);
    }

    Integer indexOf(SObject record) {
      for (Integer i = 0; i < currentSObjectRecords.size(); i++) {
        if (currentSObjectRecords[i] == record)
          return i;
      }
      throw new EventRelayException(
        'SObject handler result item is not part of the current batch.'
      );
    }

    Integer indexOf(Generic record) {
      for (Integer i = 0; i < currentGenericRecords.size(); i++) {
        if (currentGenericRecords[i] == record)
          return i;
      }
      throw new EventRelayException(
        'Generic handler result item is not part of the current batch.'
      );
    }

    Boolean isGeneric(List<Event__c> workItems) {
      return workItems != null &&
        !workItems.isEmpty() &&
        workItems[0].Payload_Type__c == consts.GENERIC_PAYLOAD;
    }

    List<Generic> toGenericRecords(List<SObject> records) {
      List<Generic> genericRecords = new List<Generic>();
      if (records == null)
        return genericRecords;

      for (SObject record : records)
        genericRecords.add(new Generic(record.getPopulatedFieldsAsMap()));
      return genericRecords;
    }

    void reset() {
      results = new List<ProcessResult>();
      currentSObjectRecords = new List<SObject>();
      currentGenericRecords = new List<Generic>();
    }
  }

  public virtual with sharing class HandlerService extends EventRelayHandlerService {
  }

  public virtual with sharing class Publisher {
    List<PublishResult> results = new List<PublishResult>();
    List<SObject> currentSObjectRecords = new List<SObject>();
    List<Generic> currentGenericRecords = new List<Generic>();

    public virtual List<PublishResult> publish(
      List<PublishPayload> publishPayloads
    ) {
      try {
        results = successResults(publishPayloads);
        if (isGeneric(publishPayloads)) {
          currentGenericRecords = payloads.toGenericList(publishPayloads);
          execute(currentGenericRecords);
        } else {
          currentSObjectRecords = payloads.toPlatformEvents(publishPayloads);
          execute(currentSObjectRecords);
        }
        return new List<PublishResult>(results);
      } finally {
        results = new List<PublishResult>();
        currentSObjectRecords = new List<SObject>();
        currentGenericRecords = new List<Generic>();
      }
    }

    public virtual void execute(List<SObject> records) {
      throw new EventRelayException(
        'Publisher does not support SObject payloads.'
      );
    }

    public virtual void execute(List<Generic> records) {
      throw new EventRelayException(
        'Publisher does not support generic payloads.'
      );
    }

    public void complete(SObject record) {
      mark(indexOf(record), true, null);
    }

    public void complete(Generic record) {
      mark(indexOf(record), true, null);
    }

    public void fail(SObject record, String message) {
      mark(indexOf(record), false, message);
    }

    public void fail(Generic record, String message) {
      mark(indexOf(record), false, message);
    }

    void mark(Integer index, Boolean success, String message) {
      if (index == null || index < 0 || index >= results.size()) {
        throw new EventRelayException(
          'Publisher result item is not part of the current batch.'
        );
      }
      results[index] = new PublishResult(success, message);
    }

    Integer indexOf(SObject record) {
      for (Integer i = 0; i < currentSObjectRecords.size(); i++) {
        if (currentSObjectRecords[i] == record)
          return i;
      }
      throw new EventRelayException(
        'SObject publisher result item is not part of the current batch.'
      );
    }

    Integer indexOf(Generic record) {
      for (Integer i = 0; i < currentGenericRecords.size(); i++) {
        if (currentGenericRecords[i] == record)
          return i;
      }
      throw new EventRelayException(
        'Generic publisher result item is not part of the current batch.'
      );
    }

    Boolean isGeneric(List<PublishPayload> publishPayloads) {
      return publishPayloads != null &&
        !publishPayloads.isEmpty() &&
        publishPayloads[0].payloadType == consts.GENERIC_PAYLOAD;
    }
  }

  public virtual with sharing class PlatformEventPublisher extends Publisher {
    public override List<PublishResult> publish(
      List<PublishPayload> publishPayloads
    ) {
      List<PublishResult> results = new List<PublishResult>();
      for (
        Database.SaveResult saveResult : EventBus.publish(
          payloads.toPlatformEvents(publishPayloads)
        )
      ) {
        results.add(toResult(saveResult));
      }
      return results;
    }

    PublishResult toResult(Database.SaveResult saveResult) {
      if (saveResult == null)
        return new PublishResult(false, 'EventBus.publish returned no result.');
      if (saveResult.isSuccess())
        return new PublishResult(true, null);

      List<String> messages = new List<String>();
      for (Database.Error error : saveResult.getErrors())
        messages.add(error.getMessage());
      return new PublishResult(false, String.join(messages, '; '));
    }
  }

  public virtual with sharing class PublisherService extends EventRelayPublisherService {
  }

  public virtual with sharing class MetadataService extends EventRelayMetadataService {
  }

  public virtual with sharing class RouteService extends EventRelayRouteService {
  }

  public virtual with sharing class WakeService {
    public virtual void signal() {
      EventBus.publish(new EventRelay_Wake__e());
    }
  }

  public with sharing class Route {
    public String route;
    public String apexClass;
    public String publisherClass;
    public String payloadType;
    public String threadKey;
    public String idempotencyKeyPath;

    public Route(
      String route,
      String apexClass,
      String payloadType,
      String threadKey
    ) {
      this(route, apexClass, payloadType, threadKey, null);
    }

    public Route(
      String route,
      String apexClass,
      String payloadType,
      String threadKey,
      String idempotencyKeyPath
    ) {
      this.route = route;
      this.apexClass = apexClass;
      this.publisherClass = apexClass;
      this.payloadType = payloadType;
      this.threadKey = threadKey;
      this.idempotencyKeyPath = idempotencyKeyPath;
    }
  }

  static List<PublishResult> successResults(
    List<PublishPayload> publishPayloads
  ) {
    List<PublishResult> results = new List<PublishResult>();
    if (publishPayloads == null)
      return results;

    for (PublishPayload publishPayload : publishPayloads) {
      results.add(new PublishResult(true, null));
    }
    return results;
  }

  static List<ProcessResult> successProcessResults(Integer resultCount) {
    List<ProcessResult> results = new List<ProcessResult>();
    if (resultCount == null)
      return results;

    for (Integer i = 0; i < resultCount; i++) {
      results.add(new ProcessResult(consts.DONE, null));
    }
    return results;
  }

  static void continueAfterJob(
    Id threadId,
    Set<Id> workItemIds,
    Integer failures,
    String runKey,
    FinalizerContext context
  ) {
    Thread.setCurrent(threadId);
    Thread.service.isFinalizer = true;
    try {
      if (context.getResult() == ParentJobResult.SUCCESS) {
        Thread.continueCurrent(runKey);
        return;
      }

      Exception error = context.getException();
      work.fail(
        workItemIds,
        error == null
          ? String.valueOf(context.getResult())
          : error.getMessage(),
        error == null ? null : error.getStackTraceString()
      );
      Thread.continueCurrent((failures == null ? 0 : failures) + 1, runKey);
    } finally {
      Thread.service.isFinalizer = false;
    }
  }

  public with sharing class PublishPayload {
    public Id workItemId;
    public String route;
    public String payloadType;
    public Generic payload;

    public PublishPayload(
      Id workItemId,
      String route,
      String payloadType,
      Generic payload
    ) {
      this.workItemId = workItemId;
      this.route = route;
      this.payloadType = payloadType;
      this.payload = payload;
    }
  }

  public with sharing class PublishResult {
    public Boolean success;
    public String message;

    public PublishResult(Boolean success, String message) {
      this.success = success == true;
      this.message = message;
    }
  }

  public with sharing class ProcessResult {
    public String status;
    public String message;

    public ProcessResult(String status, String message) {
      this.status = String.isBlank(status) ? consts.DONE : status.trim();
      this.message = message;
    }
  }

  public with sharing class PublishJob implements Queueable, Database.AllowsCallouts {
    Id threadId;
    Integer failures;
    List<Id> workItemIds;
    String runKey;

    public PublishJob(
      Id threadId,
      List<Id> workItemIds,
      Integer failures,
      String runKey
    ) {
      this.threadId = threadId;
      this.workItemIds = workItemIds == null ? new List<Id>() : workItemIds;
      this.failures = failures == null ? 0 : failures;
      this.runKey = runKey;
    }

    public void enqueue() {
      System.enqueueJob(this);
    }

    public void execute(QueueableContext context) {
      Thread.setCurrent(threadId);
      jobs.attachFinalizer(jobs.watch(threadId, workItemIds, failures, runKey));

      List<Event__c> workItems = queries.getWorkItemsById(workItemIds);
      work.applyResults(
        workItems,
        publishers.forWorkItems(workItems)
          .publish(payloads.toPublishPayloads(workItems))
      );
    }
  }

  public with sharing class ProcessJob implements Queueable, Database.AllowsCallouts {
    Id threadId;
    Integer failures;
    List<Id> workItemIds;
    String runKey;

    public ProcessJob(
      Id threadId,
      List<Id> workItemIds,
      Integer failures,
      String runKey
    ) {
      this.threadId = threadId;
      this.workItemIds = workItemIds == null ? new List<Id>() : workItemIds;
      this.failures = failures == null ? 0 : failures;
      this.runKey = runKey;
    }

    public void enqueue() {
      System.enqueueJob(this);
    }

    public void execute(QueueableContext context) {
      Thread.setCurrent(threadId);
      jobs.attachFinalizer(
        jobs.watchProcess(threadId, workItemIds, failures, runKey)
      );

      List<Event__c> workItems = queries.getWorkItemsById(workItemIds);
      work.applyProcessResults(
        workItems,
        handlers.forWorkItems(workItems).process(workItems)
      );
    }
  }

  public with sharing class PublishWatcher implements Finalizer {
    Id threadId;
    Integer failures;
    Set<Id> workItemIds;
    String runKey;

    public PublishWatcher(
      Id threadId,
      List<Id> workItemIds,
      Integer failures,
      String runKey
    ) {
      this.threadId = threadId;
      this.workItemIds = workItemIds == null
        ? new Set<Id>()
        : new Set<Id>(workItemIds);
      this.failures = failures == null ? 0 : failures;
      this.runKey = runKey;
    }

    public void execute(FinalizerContext context) {
      continueAfterJob(threadId, workItemIds, failures, runKey, context);
    }
  }

  public with sharing class ProcessWatcher implements Finalizer {
    Id threadId;
    Integer failures;
    Set<Id> workItemIds;
    String runKey;

    public ProcessWatcher(
      Id threadId,
      List<Id> workItemIds,
      Integer failures,
      String runKey
    ) {
      this.threadId = threadId;
      this.workItemIds = workItemIds == null
        ? new Set<Id>()
        : new Set<Id>(workItemIds);
      this.failures = failures == null ? 0 : failures;
      this.runKey = runKey;
    }

    public void execute(FinalizerContext context) {
      continueAfterJob(threadId, workItemIds, failures, runKey, context);
    }
  }

  public virtual with sharing class ThreadDispatcher extends ThreadRunner.Dispatcher {
    public override void dispatch(Id threadId, Integer failures) {
      jobs.enqueueNextPublishJob(threadId, failures);
    }

    public override void dispatch(
      Id threadId,
      Integer failures,
      String runKey
    ) {
      jobs.enqueueNextPublishJob(threadId, failures, runKey);
    }

    public override Boolean hasPendingWork(Id threadId) {
      return queries.hasPendingWork(threadId);
    }

    public override Boolean hasRecoverableWork(Id threadId) {
      return queries.hasRecoverableWork(threadId);
    }

    public override void prepareRecovery(Id threadId) {
      work.prepareRecovery(threadId);
    }

    public override Boolean isUserScoped() {
      return false;
    }

    public override String fallbackPoolAfterDrain() {
      return Thread.consts.ASYNC_POOL;
    }
  }

  public virtual with sharing class ProcessThreadDispatcher extends ThreadRunner.Dispatcher {
    public override void dispatch(Id threadId, Integer failures) {
      jobs.enqueueNextProcessJob(threadId, failures);
    }

    public override void dispatch(
      Id threadId,
      Integer failures,
      String runKey
    ) {
      jobs.enqueueNextProcessJob(threadId, failures, runKey);
    }

    public override Boolean hasPendingWork(Id threadId) {
      return !queries.getPendingProcessWorkItems(threadId, 1).isEmpty();
    }

    public override Boolean hasRecoverableWork(Id threadId) {
      return hasPendingWork(threadId) ||
        !queries.getRunningWorkItemIds(threadId, consts.PROCESS).isEmpty();
    }

    public override void prepareRecovery(Id threadId) {
      work.prepareRecovery(threadId, consts.PROCESS);
    }

    public override Boolean isUserScoped() {
      return false;
    }

    public override String fallbackPoolAfterDrain() {
      return Thread.consts.ASYNC_POOL;
    }
  }

  public virtual with sharing class SettingsService {
    public virtual Integer batchSize() {
      return 50;
    }

    public virtual Integer limitThresholdPct() {
      return 90;
    }
  }

  public class EventRelayException extends Exception {
  }
}
