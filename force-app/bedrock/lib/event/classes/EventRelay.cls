public virtual with sharing class EventRelay {
    public static final String PUBLISH_POOL = 'EventRelayPublish';
    public static final String PUBLISH = 'Publish';
    public static final String PENDING = 'Pending';
    public static final String RUNNING = 'Running';
    public static final String PAUSED = 'Paused';
    public static final String DONE = 'Done';
    public static final String ERROR = 'Error';

    public static JobService jobs = new JobService();
    public static WorkService work = new WorkService();
    public static QueryService queries = new QueryService();
    public static PayloadService payloads = new PayloadService();
    public static Publisher publisher = new PlatformEventPublisher();
    public static SettingsService settings = new SettingsService();

    @testVisible static void reset() {
        jobs = new JobService();
        work = new WorkService();
        queries = new QueryService();
        payloads = new PayloadService();
        publisher = new PlatformEventPublisher();
        settings = new SettingsService();
        Thread.reset();
    }

    public static List<Id> publish(List<SObject> events) {
        return work.create(events);
    }

    public static void stage(List<SObject> events) {
        work.stage(events);
    }

    public static List<Id> flush() {
        return work.flush();
    }

    public virtual with sharing class WorkService {
        @testVisible List<SObject> buffer = new List<SObject>();

        public virtual void stage(List<SObject> events) {
            if (events == null || events.isEmpty()) return;

            buffer.addAll(events);
        }

        public virtual List<Id> flush() {
            if (buffer.isEmpty()) return new List<Id>();

            List<SObject> events = new List<SObject>(buffer);
            buffer.clear();
            return create(events);
        }

        public virtual List<Id> create(List<SObject> events) {
            List<Event__c> workItems = newWorkItems(events);
            if (workItems.isEmpty()) return new List<Id>();

            DML.insertRecords(workItems);
            jobs.enqueue(workItems);
            return idsFrom(workItems);
        }

        public virtual List<Event__c> newWorkItems(List<SObject> events) {
            List<Event__c> workItems = new List<Event__c>();
            if (events == null || events.isEmpty()) return workItems;

            Integer order = 0;
            for (SObject eventRecord : events) {
                String eventType = eventType(eventRecord);
                Id threadId = Thread.currentOrCreate(PUBLISH_POOL, eventType);
                Event__c workItem = new Event__c(
                    Apex__c = 'EventRelay.PlatformEventPublisher',
                    Job_Type__c = PUBLISH,
                    Status__c = PENDING,
                    Route__c = eventType,
                    Payload_Type__c = eventType,
                    Thread__c = threadId,
                    Thread_Key__c = eventType,
                    Order__c = order,
                    Retry_Count__c = 0
                );
                payloads.write(workItem, payloads.serialize(eventRecord));
                workItems.add(workItem);
                order++;
            }
            return workItems;
        }

        public virtual void running(Set<Id> workItemIds) {
            updateStatus(workItemIds, new Event__c(Status__c = RUNNING));
        }

        public virtual void complete(Set<Id> workItemIds) {
            updateStatus(workItemIds, new Event__c(Status__c = DONE));
        }

        public virtual void pause(Set<Id> workItemIds, String message) {
            updateStatus(workItemIds, new Event__c(Status__c = PAUSED, Error_Message__c = truncate(message)));
        }

        public virtual void fail(Set<Id> workItemIds, String message, String stackTrace) {
            updateStatus(workItemIds, new Event__c(
                Status__c = ERROR,
                Error_Message__c = truncate(message),
                Error_Stack_Trace__c = truncate(stackTrace)
            ));
        }

        public virtual void applyResults(List<Event__c> workItems, List<PublishResult> results) {
            if (workItems == null || workItems.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            List<PublishResult> safeResults = results == null ? new List<PublishResult>() : results;
            for (Integer i = 0; i < workItems.size(); i++) {
                PublishResult result = i < safeResults.size()
                    ? safeResults[i]
                    : new PublishResult(false, 'Publisher returned no result for work item ' + workItems[i].Id);

                Event__c updateRecord = new Event__c(Id = workItems[i].Id);
                updateRecord.Status__c = result.success ? DONE : ERROR;
                if (!result.success) updateRecord.Error_Message__c = truncate(result.message);
                updates.add(updateRecord);
            }
            DML.updateRecords(updates);
        }

        public virtual void prepareRecovery(Id threadId) {
            updateStatus(queries.getRunningWorkItemIds(threadId), new Event__c(Status__c = PENDING));
        }

        void updateStatus(Set<Id> workItemIds, Event__c values) {
            if (workItemIds == null || workItemIds.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            for (Id workItemId : workItemIds) {
                Event__c updateRecord = new Event__c(Id = workItemId);
                if (values.Status__c != null) updateRecord.Status__c = values.Status__c;
                if (values.Error_Message__c != null) updateRecord.Error_Message__c = values.Error_Message__c;
                if (values.Error_Stack_Trace__c != null) updateRecord.Error_Stack_Trace__c = values.Error_Stack_Trace__c;
                updates.add(updateRecord);
            }
            DML.updateRecords(updates);
        }

        List<Id> idsFrom(List<Event__c> workItems) {
            List<Id> ids = new List<Id>();
            for (Event__c workItem : workItems) {
                if (workItem.Id != null) ids.add(workItem.Id);
            }
            return ids;
        }

        String eventType(SObject eventRecord) {
            if (eventRecord == null) {
                throw new EventRelayException('EventRelay.publish requires platform event records.');
            }

            String eventType = eventRecord.getSObjectType().getDescribe().getName();
            if (!eventType.endsWith('__e')) {
                throw new EventRelayException('EventRelay.publish only accepts platform event SObjects.');
            }
            return eventType;
        }

        String truncate(String value) {
            if (value == null || value.length() <= 32768) return value;

            return value.substring(0, 32768);
        }
    }

    public virtual with sharing class JobService {
        @testVisible PublishWatcher watcher;

        public virtual void enqueue(List<Event__c> workItems) {
            if (Thread.currentId() == null && workItems != null && !workItems.isEmpty()) {
                Thread.setCurrent(workItems[0].Thread__c);
            }
            Thread.enqueue();
        }

        public virtual void enqueueNextPublishJob(Id threadId, Integer failures) {
            enqueueNextPublishJob(threadId, failures, Thread.service.currentRunKey(threadId));
        }

        public virtual void enqueueNextPublishJob(Id threadId, Integer failures, String runKey) {
            if (!Limiter.isSafe(Limiter.types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS, settings.limitThresholdPct())) {
                work.pause(queries.getPendingWorkItemIds(threadId, settings.batchSize()),
                    'Platform Event publication limit is not safe.');
                Thread.continueCurrent(failures, runKey);
                return;
            }

            List<Event__c> workItems = queries.getPendingWorkItems(threadId, settings.batchSize());
            if (workItems.isEmpty()) {
                Thread.continueCurrent(failures, runKey);
                return;
            }

            Set<Id> workItemIds = idsFrom(workItems);
            work.running(workItemIds);
            new PublishJob(threadId, workItemIds, failures, runKey).enqueue();
        }

        public virtual PublishWatcher watch(Id threadId, Set<Id> workItemIds, Integer failures, String runKey) {
            watcher = new PublishWatcher(threadId, workItemIds, failures, runKey);
            return watcher;
        }

        public virtual void attachFinalizer(Finalizer finalizer) {
            System.attachFinalizer(finalizer);
        }

        Set<Id> idsFrom(List<Event__c> workItems) {
            Set<Id> ids = new Set<Id>();
            for (Event__c workItem : workItems) ids.add(workItem.Id);
            return ids;
        }
    }

    public virtual with sharing class QueryService {
        public virtual List<Event__c> getPendingWorkItems(Id threadId, Integer batchSize) {
            Integer safeBatchSize = batchSize == null || batchSize < 1 ? settings.batchSize() : batchSize;
            return (List<Event__c>) Query.records(Database.query(
                'SELECT Id, Payload_Type__c, Payload1__c, Payload2__c, Payload3__c, Payload4__c ' +
                'FROM Event__c ' +
                'WHERE Thread__c = :threadId ' +
                    'AND Job_Type__c = \'Publish\' ' +
                    'AND Status__c = \'Pending\' ' +
                'ORDER BY CreatedDate ASC, Order__c ASC, Name ASC ' +
                'LIMIT :safeBatchSize'
            ));
        }

        public virtual Boolean hasPendingWork(Id threadId) {
            return !getPendingWorkItems(threadId, 1).isEmpty();
        }

        public virtual Boolean hasRecoverableWork(Id threadId) {
            return hasPendingWork(threadId) || !getRunningWorkItemIds(threadId).isEmpty();
        }

        public virtual Set<Id> getPendingWorkItemIds(Id threadId, Integer batchSize) {
            Set<Id> workItemIds = new Set<Id>();
            for (Event__c workItem : getPendingWorkItems(threadId, batchSize)) workItemIds.add(workItem.Id);
            return workItemIds;
        }

        public virtual Set<Id> getRunningWorkItemIds(Id threadId) {
            Set<Id> workItemIds = new Set<Id>();
            for (Event__c workItem : (List<Event__c>) Query.records([
                SELECT Id
                FROM Event__c
                WHERE Thread__c = :threadId
                    AND Job_Type__c = 'Publish'
                    AND Status__c = 'Running'
            ])) {
                workItemIds.add(workItem.Id);
            }
            return workItemIds;
        }

        public virtual List<Event__c> getWorkItemsById(Set<Id> workItemIds) {
            if (workItemIds == null || workItemIds.isEmpty()) return new List<Event__c>();

            return (List<Event__c>) Query.records([
                SELECT Id, Payload_Type__c, Payload1__c, Payload2__c, Payload3__c, Payload4__c
                FROM Event__c
                WHERE Id IN :workItemIds
            ]);
        }
    }

    public virtual with sharing class PayloadService {
        public virtual String serialize(SObject eventRecord) {
            return JSON.serialize(eventRecord.getPopulatedFieldsAsMap());
        }

        public virtual List<SObject> toSObjects(List<Event__c> workItems) {
            List<SObject> events = new List<SObject>();
            if (workItems == null) return events;

            for (Event__c workItem : workItems) events.add(toSObject(workItem));
            return events;
        }

        public virtual SObject toSObject(Event__c workItem) {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(workItem.Payload_Type__c);
            if (sObjectType == null) {
                throw new EventRelayException('Unknown platform event type ' + workItem.Payload_Type__c + '.');
            }

            SObject eventRecord = sObjectType.newSObject();
            Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(read(workItem));
            Map<String, Schema.SObjectField> fields = sObjectType.getDescribe().fields.getMap();
            for (String fieldName : values.keySet()) {
                if (fields.containsKey(fieldName)) {
                    eventRecord.put(fieldName, values.get(fieldName));
                }
            }
            return eventRecord;
        }

        public virtual void write(Event__c workItem, String payload) {
            if (payload == null) payload = '';
            if (payload.length() > chunkSize() * 4) {
                throw new EventRelayException('Event payload exceeds EventRelay storage capacity.');
            }

            workItem.Payload1__c = chunk(payload, 0);
            workItem.Payload2__c = chunk(payload, 1);
            workItem.Payload3__c = chunk(payload, 2);
            workItem.Payload4__c = chunk(payload, 3);
        }

        public virtual String read(Event__c workItem) {
            return value(workItem.Payload1__c)
                + value(workItem.Payload2__c)
                + value(workItem.Payload3__c)
                + value(workItem.Payload4__c);
        }

        Integer chunkSize() {
            return 32768;
        }

        String chunk(String value, Integer index) {
            Integer startIndex = chunkSize() * index;
            if (value.length() <= startIndex) return null;

            Integer endIndex = Math.min(value.length(), startIndex + chunkSize());
            return value.substring(startIndex, endIndex);
        }

        String value(String text) {
            return text == null ? '' : text;
        }
    }

    public virtual with sharing class Publisher {
        public virtual List<PublishResult> publish(List<SObject> events) {
            return new List<PublishResult>();
        }
    }

    public virtual with sharing class PlatformEventPublisher extends Publisher {
        public override List<PublishResult> publish(List<SObject> events) {
            List<PublishResult> results = new List<PublishResult>();
            for (Database.SaveResult saveResult : EventBus.publish(events)) {
                results.add(toResult(saveResult));
            }
            return results;
        }

        PublishResult toResult(Database.SaveResult saveResult) {
            if (saveResult == null) return new PublishResult(false, 'EventBus.publish returned no result.');
            if (saveResult.isSuccess()) return new PublishResult(true, null);

            List<String> messages = new List<String>();
            for (Database.Error error : saveResult.getErrors()) messages.add(error.getMessage());
            return new PublishResult(false, String.join(messages, '; '));
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

    public with sharing class PublishJob implements Queueable {
        Id threadId;
        Integer failures;
        Set<Id> workItemIds;
        String runKey;

        public PublishJob(Id threadId, Set<Id> workItemIds, Integer failures, String runKey) {
            this.threadId = threadId;
            this.workItemIds = workItemIds == null ? new Set<Id>() : workItemIds;
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
            work.applyResults(workItems, publisher.publish(payloads.toSObjects(workItems)));
        }
    }

    public with sharing class PublishWatcher implements Finalizer {
        Id threadId;
        Integer failures;
        Set<Id> workItemIds;
        String runKey;

        public PublishWatcher(Id threadId, Set<Id> workItemIds, Integer failures, String runKey) {
            this.threadId = threadId;
            this.workItemIds = workItemIds == null ? new Set<Id>() : workItemIds;
            this.failures = failures == null ? 0 : failures;
            this.runKey = runKey;
        }

        public void execute(FinalizerContext context) {
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
                    error == null ? String.valueOf(context.getResult()) : error.getMessage(),
                    error == null ? null : error.getStackTraceString()
                );
                Thread.continueCurrent(failures + 1, runKey);
            } finally {
                Thread.service.isFinalizer = false;
            }
        }
    }

    public virtual with sharing class ThreadDispatcher extends ThreadRunner.Dispatcher {
        public override void dispatch(Id threadId, Integer failures) {
            jobs.enqueueNextPublishJob(threadId, failures);
        }

        public override void dispatch(Id threadId, Integer failures, String runKey) {
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
    }

    public virtual with sharing class SettingsService {
        public virtual Integer batchSize() {
            return 50;
        }

        public virtual Integer limitThresholdPct() {
            return 90;
        }
    }

    public class EventRelayException extends Exception {}
}
