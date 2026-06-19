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

    @testVisible static void reset() {
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
        public String PLATFORM_EVENT_PUBLISHER = PlatformEventPublisher.class.getName();
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
        if (!Thread.service.canEnqueue() || Thread.service.hasEnqueued || System.isQueueable() || Thread.service.isFinalizer) return;

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
        return normalizedPool == consts.PUBLISH_POOL || normalizedPool == consts.PROCESS_POOL;
    }

    static String idempotencyLookupKey(Event__c workItem) {
        return JSON.serialize(new List<String>{
            workItem.Job_Type__c,
            workItem.Route__c,
            workItem.Idempotency_Key__c
        });
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

        public virtual List<Id> createProcess(List<SObject> events, Type handlerType) {
            List<Event__c> workItems = newProcessWorkItems(events, handlerType);
            return create(workItems);
        }

        public virtual List<Id> createProcess(List<Generic> genericPayloads) {
            List<Event__c> workItems = newProcessWorkItems(genericPayloads, null);
            return create(workItems);
        }

        public virtual List<Id> createProcess(List<Generic> genericPayloads, Type handlerType) {
            List<Event__c> workItems = newProcessWorkItems(genericPayloads, handlerType);
            return create(workItems);
        }

        public virtual List<Id> create(List<Event__c> workItems) {
            if (workItems.isEmpty()) return new List<Id>();

            markStaleWork(workItems);
            DML.insertRecords(workItems);
            List<Event__c> runnableWorkItems = runnableWorkItems(workItems);
            Thread.reopen(threadIdsFrom(runnableWorkItems));
            jobs.enqueue(runnableWorkItems);
            return idsFrom(workItems);
        }

        public virtual List<Event__c> newWorkItems(List<SObject> events, Type publisherType) {
            List<Event__c> workItems = new List<Event__c>();
            if (events == null || events.isEmpty()) return workItems;

            Integer order = 0;
            for (SObject eventRecord : events) {
                String eventType = eventType(eventRecord);
                for (Route route : sObjectRoutes(eventType, publisherType)) {
                    Id threadId = Thread.currentOrCreate(consts.PUBLISH_POOL, route.threadKey);
                    Event__c workItem = newWorkItem(route, consts.PUBLISH, route.payloadType, threadId, order);
                    workItem.Idempotency_Key__c = idempotencyKey(eventRecord, route);
                    payloads.write(workItem, payloads.serialize(eventRecord));
                    workItems.add(workItem);
                    order++;
                }
            }
            return workItems;
        }

        public virtual List<Event__c> newWorkItems(List<Generic> genericPayloads) {
            List<Event__c> workItems = new List<Event__c>();
            if (genericPayloads == null || genericPayloads.isEmpty()) return workItems;

            Integer order = 0;
            for (Generic payload : genericPayloads) {
                if (payload == null) {
                    throw new EventRelayException('EventRelay.publish requires non-null generic payloads.');
                }

                List<Route> resolvedRoutes = routes.forGeneric(payload, consts.PUBLISH);
                if (resolvedRoutes == null || resolvedRoutes.isEmpty()) {
                    throw new EventRelayException('EventRelay.publish requires route metadata for generic payloads.');
                }

                for (Route route : resolvedRoutes) {
                    Id threadId = Thread.currentOrCreate(consts.PUBLISH_POOL, route.threadKey);
                    Event__c workItem = newWorkItem(route, consts.PUBLISH, consts.GENERIC_PAYLOAD, threadId, order);
                    workItem.Idempotency_Key__c = idempotencyKey(payload, route);
                    payloads.write(workItem, payload.json());
                    workItems.add(workItem);
                    order++;
                }
            }
            return workItems;
        }

        public virtual List<Event__c> newProcessWorkItems(List<SObject> events, Type handlerType) {
            List<Event__c> workItems = new List<Event__c>();
            if (events == null || events.isEmpty()) return workItems;

            Integer order = 0;
            for (SObject eventRecord : events) {
                String eventType = eventType(eventRecord);
                for (Route route : sObjectProcessRoutes(eventType, handlerType)) {
                    Id threadId = Thread.currentOrCreate(consts.PROCESS_POOL, route.threadKey);
                    Event__c workItem = newWorkItem(route, consts.PROCESS, route.payloadType, threadId, order);
                    workItem.Idempotency_Key__c = idempotencyKey(eventRecord, route);
                    payloads.write(workItem, payloads.serialize(eventRecord));
                    workItems.add(workItem);
                    order++;
                }
            }
            return workItems;
        }

        public virtual List<Event__c> newProcessWorkItems(List<Generic> genericPayloads, Type handlerType) {
            List<Event__c> workItems = new List<Event__c>();
            if (genericPayloads == null || genericPayloads.isEmpty()) return workItems;

            Integer order = 0;
            for (Generic payload : genericPayloads) {
                if (payload == null) {
                    throw new EventRelayException('EventRelay.ingest requires non-null generic payloads.');
                }

                for (Route route : genericProcessRoutes(payload, handlerType)) {
                    Id threadId = Thread.currentOrCreate(consts.PROCESS_POOL, route.threadKey);
                    Event__c workItem = newWorkItem(route, consts.PROCESS, consts.GENERIC_PAYLOAD, threadId, order);
                    workItem.Idempotency_Key__c = idempotencyKey(payload, route);
                    payloads.write(workItem, payload.json());
                    workItems.add(workItem);
                    order++;
                }
            }
            return workItems;
        }

        Event__c newWorkItem(Route route, String jobType, String payloadType, Id threadId, Integer order) {
            return new Event__c(
                Apex__c = route.apexClass,
                Job_Type__c = jobType,
                Status__c = consts.PENDING,
                Route__c = route.route,
                Payload_Type__c = payloadType,
                Thread__c = threadId,
                Thread_Key__c = route.threadKey,
                Order__c = order,
                Retry_Count__c = 0
            );
        }

        void markStaleWork(List<Event__c> workItems) {
            Map<String, Event__c> acceptedWorkByKey = queries.getAcceptedWorkByIdempotencyKey(workItems);
            for (Event__c workItem : workItems) {
                if (String.isBlank(workItem.Idempotency_Key__c)) continue;

                String lookupKey = EventRelay.idempotencyLookupKey(workItem);
                if (acceptedWorkByKey.containsKey(lookupKey)) {
                    markStale(workItem, acceptedWorkByKey.get(lookupKey));
                    continue;
                }
                acceptedWorkByKey.put(lookupKey, workItem);
            }
        }

        void markStale(Event__c workItem, Event__c acceptedWork) {
            workItem.Status__c = consts.STALE;
            workItem.Error_Message__c = acceptedWork.Id == null
                ? 'Duplicate idempotency key already accepted in this transaction.'
                : 'Duplicate idempotency key already accepted by Event work item ' + acceptedWork.Id + '.';
        }

        List<Event__c> runnableWorkItems(List<Event__c> workItems) {
            List<Event__c> runnable = new List<Event__c>();
            for (Event__c workItem : workItems) {
                if (workItem.Status__c == consts.PENDING) runnable.add(workItem);
            }
            return runnable;
        }

        String idempotencyKey(SObject eventRecord, Route route) {
            if (route == null || String.isBlank(route.idempotencyKeyPath)) return null;

            String fieldName = route.idempotencyKeyPath.trim();
            try {
                return normalizedIdempotencyKey(eventRecord.get(fieldName));
            } catch (Exception e) {
                throw new EventRelayException('Event route ' + route.route + ' has invalid idempotency key field ' + fieldName + '.');
            }
        }

        String idempotencyKey(Generic payload, Route route) {
            if (route == null || String.isBlank(route.idempotencyKeyPath)) return null;

            return normalizedIdempotencyKey(payload.get(route.idempotencyKeyPath.trim(), String.class));
        }

        String normalizedIdempotencyKey(Object value) {
            if (value == null) return null;

            String key = String.valueOf(value).trim();
            if (String.isBlank(key)) return null;
            if (key.length() > 255) {
                throw new EventRelayException('EventRelay idempotency keys must be 255 characters or fewer.');
            }
            return key;
        }

        public virtual void running(Set<Id> workItemIds) {
            updateStatus(workItemIds, new Event__c(Status__c = consts.RUNNING));
        }

        public virtual void complete(Set<Id> workItemIds) {
            updateStatus(workItemIds, new Event__c(Status__c = consts.DONE));
        }

        public virtual List<Id> retry(Set<Id> workItemIds) {
            List<Event__c> workItems = queries.getRetryableWorkItems(workItemIds);
            if (workItems.isEmpty()) return new List<Id>();

            List<SObject> updates = new List<SObject>();
            for (Event__c workItem : workItems) {
                Event__c updateRecord = new Event__c(
                    Id = workItem.Id,
                    Status__c = consts.PENDING
                );
                updateRecord.Error_Message__c = null;
                updateRecord.Error_Stack_Trace__c = null;
                updates.add(updateRecord);
            }
            DML.updateRecords(updates);
            Thread.reopen(threadIdsFrom(workItems));
            jobs.enqueue(workItems);
            return idsFrom(workItems);
        }

        public virtual void fail(Set<Id> workItemIds, String message, String stackTrace) {
            applyFailure(
                queries.getWorkItemsById(workItemIds),
                new PublishResult(false, message),
                stackTrace
            );
        }

        public virtual void applyResults(List<Event__c> workItems, List<PublishResult> results) {
            if (workItems == null || workItems.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            List<PublishResult> safeResults = results == null ? new List<PublishResult>() : results;
            for (Integer i = 0; i < workItems.size(); i++) {
                PublishResult result = i < safeResults.size()
                    ? safeResults[i]
                    : new PublishResult(false, 'Publisher returned no result for work item ' + workItems[i].Id);

                updates.add(result.success
                    ? successUpdate(workItems[i])
                    : failureUpdate(workItems[i], result, null));
            }
            DML.updateRecords(updates);
        }

        public virtual void applyProcessResults(List<Event__c> workItems, List<ProcessResult> results) {
            if (workItems == null || workItems.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            List<ProcessResult> safeResults = results == null ? new List<ProcessResult>() : results;
            for (Integer i = 0; i < workItems.size(); i++) {
                ProcessResult result = i < safeResults.size()
                    ? safeResults[i]
                    : new ProcessResult(consts.ERROR, 'Handler returned no result for work item ' + workItems[i].Id);

                updates.add(processUpdate(workItems[i], result));
            }
            DML.updateRecords(updates);
        }

        void applyFailure(List<Event__c> workItems, PublishResult result, String stackTrace) {
            if (workItems == null || workItems.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            for (Event__c workItem : workItems) {
                updates.add(failureUpdate(workItem, result, stackTrace));
            }
            DML.updateRecords(updates);
        }

        Event__c successUpdate(Event__c workItem) {
            return new Event__c(Id = workItem.Id, Status__c = consts.DONE);
        }

        Event__c processUpdate(Event__c workItem, ProcessResult result) {
            if (result.status == consts.DONE) return successUpdate(workItem);
            return failureUpdate(workItem, new PublishResult(false, result.message), null);
        }

        Event__c failureUpdate(Event__c workItem, PublishResult result, String stackTrace) {
            Integer retryCount = retryCount(workItem);
            Boolean shouldRetry = retryCount < metadata.maxRetries(workItem.Route__c);
            Event__c updateRecord = new Event__c(
                Id = workItem.Id,
                Status__c = shouldRetry ? consts.PENDING : consts.ERROR,
                Error_Message__c = truncate(result.message),
                Error_Stack_Trace__c = truncate(stackTrace)
            );
            if (shouldRetry) updateRecord.Retry_Count__c = retryCount + 1;
            return updateRecord;
        }

        Integer retryCount(Event__c workItem) {
            if (workItem == null || workItem.Retry_Count__c == null || workItem.Retry_Count__c < 0) return 0;
            return workItem.Retry_Count__c.intValue();
        }

        public virtual void prepareRecovery(Id threadId) {
            prepareRecovery(threadId, consts.PUBLISH);
        }

        public virtual void prepareRecovery(Id threadId, String jobType) {
            updateStatus(queries.getRunningWorkItemIds(threadId, jobType), new Event__c(Status__c = consts.PENDING));
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

        Set<Id> threadIdsFrom(List<Event__c> workItems) {
            Set<Id> threadIds = new Set<Id>();
            for (Event__c workItem : workItems) {
                if (workItem.Thread__c != null) threadIds.add(workItem.Thread__c);
            }
            return threadIds;
        }

        String eventType(SObject eventRecord) {
            if (eventRecord == null) {
                throw new EventRelayException('EventRelay requires platform event records.');
            }

            String eventType = eventRecord.getSObjectType().getDescribe().getName();
            if (!eventType.endsWith('__e')) {
                throw new EventRelayException('EventRelay only accepts platform event SObjects.');
            }
            return eventType;
        }

        String publisherClass(Type publisherType) {
            if (publisherType == null) {
                throw new EventRelayException('EventRelay.publish requires a publisher class for custom publishers.');
            }
            return publisherType.getName();
        }

        List<Route> sObjectRoutes(String eventType, Type publisherType) {
            if (publisherType != null) {
                String route = eventType + ':' + publisherType.getName();
                String publisher = publisherClass(publisherType);
                return new List<Route> {
                    new Route(
                        route,
                        publisher,
                        eventType,
                        routeThreadKey(consts.PUBLISH, eventType, route),
                        routes.idempotencyKeyPathForSObject(eventType, consts.PUBLISH, publisher)
                    )
                };
            }

            List<Route> resolvedRoutes = routes.forSObject(eventType, consts.PUBLISH);
            return resolvedRoutes == null || resolvedRoutes.isEmpty()
                ? new List<Route> { defaultPlatformEventRoute(eventType) }
                : resolvedRoutes;
        }

        List<Route> sObjectProcessRoutes(String eventType, Type handlerType) {
            if (handlerType != null) {
                String route = eventType + ':' + handlerType.getName();
                String handler = handlerClass(handlerType);
                return new List<Route> {
                    new Route(
                        route,
                        handler,
                        eventType,
                        routeThreadKey(consts.PROCESS, eventType, route),
                        routes.idempotencyKeyPathForSObject(eventType, consts.INGEST, handler)
                    )
                };
            }

            List<Route> resolvedRoutes = routes.forSObject(eventType, consts.INGEST);
            if (resolvedRoutes == null || resolvedRoutes.isEmpty()) {
                throw new EventRelayException('EventRelay.ingest requires route metadata or an explicit handler class.');
            }
            return resolvedRoutes;
        }

        List<Route> genericProcessRoutes(Generic payload, Type handlerType) {
            if (handlerType != null) {
                String route = consts.GENERIC_PAYLOAD + ':' + handlerType.getName();
                String handler = handlerClass(handlerType);
                return new List<Route> {
                    new Route(
                        route,
                        handler,
                        consts.GENERIC_PAYLOAD,
                        routeThreadKey(consts.PROCESS, consts.GENERIC_PAYLOAD, route),
                        routes.idempotencyKeyPathForGeneric(payload, consts.INGEST, handler)
                    )
                };
            }

            List<Route> resolvedRoutes = routes.forGeneric(payload, consts.INGEST);
            if (resolvedRoutes == null || resolvedRoutes.isEmpty()) {
                throw new EventRelayException('EventRelay.ingest requires route metadata or an explicit handler class.');
            }
            return resolvedRoutes;
        }

        String handlerClass(Type handlerType) {
            if (handlerType == null) {
                throw new EventRelayException('EventRelay.ingest requires a handler class.');
            }
            return handlerType.getName();
        }

        String truncate(String value) {
            if (value == null || value.length() <= 32768) return value;

            return value.substring(0, 32768);
        }
    }

    public virtual with sharing class JobService {
        @testVisible PublishWatcher watcher;
        @testVisible ProcessWatcher processWatcher;

        public virtual void enqueue(List<Event__c> workItems) {
            if (workItems == null || workItems.isEmpty()) return;

            wakeSignal.signal();
        }

        public virtual void enqueueNextPublishJob(Id threadId, Integer failures) {
            enqueueNextPublishJob(threadId, failures, Thread.service.currentRunKey(threadId));
        }

        public virtual void enqueueNextPublishJob(Id threadId, Integer failures, String runKey) {
            enqueueNextJob(threadId, failures, runKey, consts.PUBLISH);
        }

        public virtual void enqueueNextProcessJob(Id threadId, Integer failures) {
            enqueueNextProcessJob(threadId, failures, Thread.service.currentRunKey(threadId));
        }

        public virtual void enqueueNextProcessJob(Id threadId, Integer failures, String runKey) {
            enqueueNextJob(threadId, failures, runKey, consts.PROCESS);
        }

        void enqueueNextJob(Id threadId, Integer failures, String runKey, String jobType) {
            List<Event__c> workItems = jobType == consts.PROCESS
                ? queries.getPendingProcessWorkItems(threadId, settings.batchSize())
                : queries.getPendingWorkItems(threadId, settings.batchSize());
            if (workItems.isEmpty()) {
                Thread.continueCurrent(failures, runKey);
                return;
            }

            List<Id> workItemIds = idsFrom(workItems);
            if (!Thread.service.canStartQueueableWork()) {
                Thread.pause(threadId, Thread.service.queueablePauseReason(), runKey);
                return;
            }

            if (jobType == consts.PUBLISH
                && publishers.requiresPlatformEventLimit(workItems)
                && !Limiter.isSafe(Limiter.types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS, settings.limitThresholdPct())) {
                Thread.pause(threadId, 'Platform Event publication limit is not safe.', runKey);
                return;
            }

            work.running(new Set<Id>(workItemIds));
            if (jobType == consts.PROCESS) {
                new ProcessJob(threadId, workItemIds, failures, runKey).enqueue();
                return;
            }
            new PublishJob(threadId, workItemIds, failures, runKey).enqueue();
        }

        public virtual PublishWatcher watch(Id threadId, List<Id> workItemIds, Integer failures, String runKey) {
            watcher = new PublishWatcher(threadId, workItemIds, failures, runKey);
            return watcher;
        }

        public virtual ProcessWatcher watchProcess(Id threadId, List<Id> workItemIds, Integer failures, String runKey) {
            processWatcher = new ProcessWatcher(threadId, workItemIds, failures, runKey);
            return processWatcher;
        }

        public virtual void attachFinalizer(Finalizer finalizer) {
            System.attachFinalizer(finalizer);
        }

        List<Id> idsFrom(List<Event__c> workItems) {
            List<Id> ids = new List<Id>();
            for (Event__c workItem : workItems) ids.add(workItem.Id);
            return ids;
        }
    }

    public virtual with sharing class QueryService {
        public virtual List<Event__c> getPendingWorkItems(Id threadId, Integer batchSize) {
            return getPendingWorkItems(threadId, batchSize, consts.PUBLISH);
        }

        public virtual List<Event__c> getPendingProcessWorkItems(Id threadId, Integer batchSize) {
            return getPendingWorkItems(threadId, batchSize, consts.PROCESS);
        }

        public virtual List<Event__c> getPendingWorkItems(Id threadId, Integer batchSize, String jobType) {
            Integer safeBatchSize = batchSize == null || batchSize < 1 ? settings.batchSize() : batchSize;
            String safeJobType = String.isBlank(jobType) ? consts.PUBLISH : jobType.trim();
            List<Event__c> heads = (List<Event__c>) Query.records(Database.query(
                'SELECT Id, Payload_Type__c, Payload1__c, Payload2__c, Payload3__c, Payload4__c ' +
                    ', Apex__c, Route__c, Retry_Count__c ' +
                'FROM Event__c ' +
                'WHERE Thread__c = :threadId ' +
                    'AND Job_Type__c = :safeJobType ' +
                    'AND Status__c = \'Pending\' ' +
                'ORDER BY CreatedDate ASC, Order__c ASC, Name ASC ' +
                'LIMIT 1'
            ));
            if (heads.isEmpty()) return new List<Event__c>();

            Event__c head = heads[0];
            safeBatchSize = metadata.batchSize(head.Route__c, safeBatchSize);

            List<Event__c> workItems = (List<Event__c>) Query.records(Database.query(
                'SELECT Id, Payload_Type__c, Payload1__c, Payload2__c, Payload3__c, Payload4__c ' +
                    ', Apex__c, Route__c, Retry_Count__c ' +
                'FROM Event__c ' +
                'WHERE Thread__c = :threadId ' +
                    'AND Job_Type__c = :safeJobType ' +
                    'AND Status__c = \'Pending\' ' +
                'ORDER BY CreatedDate ASC, Order__c ASC, Name ASC ' +
                'LIMIT :safeBatchSize'
            ));
            return firstCompatibleBatch(workItems);
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
            return getRunningWorkItemIds(threadId, consts.PUBLISH);
        }

        public virtual Set<Id> getRunningWorkItemIds(Id threadId, String jobType) {
            Set<Id> workItemIds = new Set<Id>();
            String safeJobType = String.isBlank(jobType) ? consts.PUBLISH : jobType.trim();
            String runningStatus = consts.RUNNING;
            for (Event__c workItem : (List<Event__c>) Query.records([
                SELECT Id
                FROM Event__c
                WHERE Thread__c = :threadId
                    AND Job_Type__c = :safeJobType
                    AND Status__c = :runningStatus
            ])) {
                workItemIds.add(workItem.Id);
            }
            return workItemIds;
        }

        public virtual List<Event__c> getWorkItemsById(List<Id> workItemIds) {
            if (workItemIds == null || workItemIds.isEmpty()) return new List<Event__c>();

            Map<Id, Event__c> workItemsById = new Map<Id, Event__c>((List<Event__c>) Query.records([
                SELECT Id, Apex__c, Route__c, Payload_Type__c, Retry_Count__c,
                    Payload1__c, Payload2__c, Payload3__c, Payload4__c
                FROM Event__c
                WHERE Id IN :workItemIds
            ]));

            List<Event__c> orderedWorkItems = new List<Event__c>();
            for (Id workItemId : workItemIds) {
                if (workItemsById.containsKey(workItemId)) orderedWorkItems.add(workItemsById.get(workItemId));
            }
            return orderedWorkItems;
        }

        public virtual List<Event__c> getWorkItemsById(Set<Id> workItemIds) {
            return getWorkItemsById(new List<Id>(workItemIds));
        }

        public virtual List<Event__c> getRetryableWorkItems(Set<Id> workItemIds) {
            if (workItemIds == null || workItemIds.isEmpty()) return new List<Event__c>();

            String errorStatus = consts.ERROR;
            return (List<Event__c>) Query.records([
                SELECT Id, Thread__c
                FROM Event__c
                WHERE Id IN :workItemIds
                    AND Status__c = :errorStatus
                ORDER BY CreatedDate ASC, Order__c ASC, Name ASC
            ]);
        }

        public virtual Map<String, Event__c> getAcceptedWorkByIdempotencyKey(List<Event__c> candidates) {
            Map<String, Event__c> workByKey = new Map<String, Event__c>();
            if (candidates == null || candidates.isEmpty()) return workByKey;

            Set<String> idempotencyKeys = new Set<String>();
            Set<String> lookupKeys = new Set<String>();
            for (Event__c candidate : candidates) {
                if (String.isBlank(candidate.Idempotency_Key__c)) continue;

                idempotencyKeys.add(candidate.Idempotency_Key__c);
                lookupKeys.add(EventRelay.idempotencyLookupKey(candidate));
            }
            if (idempotencyKeys.isEmpty()) return workByKey;

            Set<String> acceptedStatuses = new Set<String> { consts.PENDING, consts.RUNNING, consts.DONE };
            for (Event__c workItem : (List<Event__c>) Query.records([
                SELECT Id, Job_Type__c, Route__c, Idempotency_Key__c
                FROM Event__c
                WHERE Idempotency_Key__c IN :idempotencyKeys
                    AND Status__c IN :acceptedStatuses
                ORDER BY CreatedDate ASC, Order__c ASC, Name ASC
            ])) {
                String lookupKey = EventRelay.idempotencyLookupKey(workItem);
                if (lookupKeys.contains(lookupKey) && !workByKey.containsKey(lookupKey)) {
                    workByKey.put(lookupKey, workItem);
                }
            }
            return workByKey;
        }

        List<Event__c> firstCompatibleBatch(List<Event__c> workItems) {
            List<Event__c> batch = new List<Event__c>();
            if (workItems == null || workItems.isEmpty()) return batch;

            Event__c head = workItems[0];
            for (Event__c workItem : workItems) {
                if (workItem.Apex__c != head.Apex__c
                    || workItem.Route__c != head.Route__c
                    || workItem.Payload_Type__c != head.Payload_Type__c) {
                    break;
                }
                batch.add(workItem);
            }
            return batch;
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

        public virtual List<PublishPayload> toPublishPayloads(List<Event__c> workItems) {
            List<PublishPayload> publishPayloads = new List<PublishPayload>();
            if (workItems == null) return publishPayloads;

            for (Event__c workItem : workItems) {
                publishPayloads.add(new PublishPayload(
                    workItem.Id,
                    workItem.Route__c,
                    workItem.Payload_Type__c,
                    toGeneric(workItem)
                ));
            }
            return publishPayloads;
        }

        public virtual List<SObject> toPlatformEvents(List<PublishPayload> publishPayloads) {
            List<SObject> events = new List<SObject>();
            if (publishPayloads == null) return events;

            for (PublishPayload publishPayload : publishPayloads) events.add(toSObject(publishPayload));
            return events;
        }

        public virtual List<Generic> toGenericList(List<PublishPayload> publishPayloads) {
            List<Generic> records = new List<Generic>();
            if (publishPayloads == null) return records;

            for (PublishPayload publishPayload : publishPayloads) records.add(publishPayload.payload);
            return records;
        }

        public virtual List<Generic> toGenericEvents(List<Event__c> workItems) {
            List<Generic> records = new List<Generic>();
            if (workItems == null) return records;

            for (Event__c workItem : workItems) records.add(toGeneric(workItem));
            return records;
        }

        public virtual SObject toSObject(Event__c workItem) {
            return toSObject(new PublishPayload(
                workItem.Id,
                workItem.Route__c,
                workItem.Payload_Type__c,
                toGeneric(workItem)
            ));
        }

        public virtual SObject toSObject(PublishPayload publishPayload) {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(publishPayload.payloadType);
            if (sObjectType == null) {
                throw new EventRelayException('Unknown platform event type ' + publishPayload.payloadType + '.');
            }

            SObject eventRecord = sObjectType.newSObject();
            Map<String, Object> values = publishPayload.payload.generic();
            Map<String, Schema.SObjectField> fields = sObjectType.getDescribe().fields.getMap();
            for (String fieldName : values.keySet()) {
                if (fields.containsKey(fieldName)) {
                    eventRecord.put(fieldName, values.get(fieldName));
                }
            }
            return eventRecord;
        }

        public virtual Generic toGeneric(Event__c workItem) {
            return new Generic(read(workItem));
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

    public virtual with sharing class Handler {
        List<ProcessResult> results = new List<ProcessResult>();
        List<Generic> currentRecords = new List<Generic>();

        public virtual List<ProcessResult> process(List<Generic> records) {
            try {
                currentRecords = records == null ? new List<Generic>() : records;
                results = successProcessResults(currentRecords);
                execute(currentRecords);
                return new List<ProcessResult>(results);
            } finally {
                results = new List<ProcessResult>();
                currentRecords = new List<Generic>();
            }
        }

        public virtual void execute(List<Generic> records) {
            throw new EventRelayException('Handler must override execute(List<Generic>).');
        }

        public void complete(Generic record) {
            mark(indexOf(record), consts.DONE, null);
        }

        public void fail(Generic record, String message) {
            mark(indexOf(record), consts.ERROR, message);
        }

        void mark(Integer index, String status, String message) {
            if (index == null || index < 0 || index >= results.size()) {
                throw new EventRelayException('Handler result item is not part of the current batch.');
            }
            results[index] = new ProcessResult(status, message);
        }

        Integer indexOf(Generic record) {
            for (Integer i = 0; i < currentRecords.size(); i++) {
                if (currentRecords[i] == record) return i;
            }
            throw new EventRelayException('Generic handler result item is not part of the current batch.');
        }
    }

    public virtual with sharing class HandlerService {
        public virtual Handler forWorkItems(List<Event__c> workItems) {
            if (workItems == null || workItems.isEmpty()) return new Handler();

            String handlerClass = workItems[0].Apex__c;
            for (Event__c workItem : workItems) {
                if (workItem.Apex__c != handlerClass) {
                    throw new EventRelayException('A process batch can only contain one handler class.');
                }
            }
            return forClass(handlerClass);
        }

        public virtual Handler forClass(String handlerClass) {
            if (String.isBlank(handlerClass)) {
                throw new EventRelayException('EventRelay process work requires a handler class.');
            }

            String safeHandlerClass = handlerClass.trim();
            Type handlerType = Type.forName(safeHandlerClass);
            if (handlerType == null) {
                throw new EventRelayException('Unknown EventRelay handler class ' + safeHandlerClass + '.');
            }

            Object handlerInstance = handlerType.newInstance();
            if (!(handlerInstance instanceof Handler)) {
                throw new EventRelayException(safeHandlerClass + ' must extend EventRelay.Handler.');
            }
            return (Handler) handlerInstance;
        }
    }

    public virtual with sharing class Publisher {
        List<PublishResult> results = new List<PublishResult>();
        List<SObject> currentSObjectRecords = new List<SObject>();
        List<Generic> currentGenericRecords = new List<Generic>();

        public virtual List<PublishResult> publish(List<PublishPayload> publishPayloads) {
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
            throw new EventRelayException('Publisher does not support SObject payloads.');
        }

        public virtual void execute(List<Generic> records) {
            throw new EventRelayException('Publisher does not support generic payloads.');
        }

        public void succeed(SObject record) {
            mark(indexOf(record), true, null);
        }

        public void succeed(Generic record) {
            mark(indexOf(record), true, null);
        }

        public void complete(SObject record) {
            succeed(record);
        }

        public void complete(Generic record) {
            succeed(record);
        }

        public void fail(SObject record, String message) {
            mark(indexOf(record), false, message);
        }

        public void fail(Generic record, String message) {
            mark(indexOf(record), false, message);
        }

        void mark(Integer index, Boolean success, String message) {
            if (index == null || index < 0 || index >= results.size()) {
                throw new EventRelayException('Publisher result item is not part of the current batch.');
            }
            results[index] = new PublishResult(success, message);
        }

        Integer indexOf(SObject record) {
            for (Integer i = 0; i < currentSObjectRecords.size(); i++) {
                if (currentSObjectRecords[i] == record) return i;
            }
            throw new EventRelayException('SObject publisher result item is not part of the current batch.');
        }

        Integer indexOf(Generic record) {
            for (Integer i = 0; i < currentGenericRecords.size(); i++) {
                if (currentGenericRecords[i] == record) return i;
            }
            throw new EventRelayException('Generic publisher result item is not part of the current batch.');
        }

        Boolean isGeneric(List<PublishPayload> publishPayloads) {
            return publishPayloads != null
                && !publishPayloads.isEmpty()
                && publishPayloads[0].payloadType == consts.GENERIC_PAYLOAD;
        }
    }

    public virtual with sharing class PlatformEventPublisher extends Publisher {
        public override List<PublishResult> publish(List<PublishPayload> publishPayloads) {
            List<PublishResult> results = new List<PublishResult>();
            for (Database.SaveResult saveResult : EventBus.publish(payloads.toPlatformEvents(publishPayloads))) {
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

    public virtual with sharing class PublisherService {
        public virtual Publisher forWorkItems(List<Event__c> workItems) {
            if (workItems == null || workItems.isEmpty()) return new Publisher();

            String publisherClass = workItems[0].Apex__c;
            for (Event__c workItem : workItems) {
                if (workItem.Apex__c != publisherClass) {
                    throw new EventRelayException('A publish batch can only contain one publisher class.');
                }
            }
            return forClass(publisherClass);
        }

        public virtual Boolean requiresPlatformEventLimit(List<Event__c> workItems) {
            if (workItems == null || workItems.isEmpty()) return false;

            String publisherClass = workItems[0].Apex__c;
            return String.isBlank(publisherClass) || publisherClass == consts.PLATFORM_EVENT_PUBLISHER;
        }

        public virtual Publisher forClass(String publisherClass) {
            String safePublisherClass = String.isBlank(publisherClass)
                ? consts.PLATFORM_EVENT_PUBLISHER
                : publisherClass.trim();
            if (safePublisherClass == consts.PLATFORM_EVENT_PUBLISHER) {
                return new PlatformEventPublisher();
            }

            Type publisherType = Type.forName(safePublisherClass);
            if (publisherType == null) {
                throw new EventRelayException('Unknown EventRelay publisher class ' + safePublisherClass + '.');
            }

            Object publisherInstance = publisherType.newInstance();
            if (!(publisherInstance instanceof Publisher)) {
                throw new EventRelayException(safePublisherClass + ' must extend EventRelay.Publisher.');
            }
            return (Publisher) publisherInstance;
        }
    }

    public virtual with sharing class MetadataService {
        @testVisible List<Event_Config__mdt> configs;
        @testVisible Map<String, Event_Config__mdt> configByDeveloperName;

        public virtual List<Event_Config__mdt> getConfigs() {
            if (configs == null) configs = loadConfigs();
            return configs;
        }

        public virtual Event_Config__mdt getConfig(String developerName) {
            if (String.isBlank(developerName)) return null;
            if (configByDeveloperName == null) {
                configByDeveloperName = new Map<String, Event_Config__mdt>();
                for (Event_Config__mdt config : getConfigs()) {
                    configByDeveloperName.put(config.DeveloperName, config);
                }
            }
            return configByDeveloperName.get(developerName.trim());
        }

        public virtual Integer batchSize(String route, Integer defaultBatchSize) {
            Integer safeDefault = defaultBatchSize == null || defaultBatchSize < 1 ? settings.batchSize() : defaultBatchSize;
            Event_Config__mdt config = getConfig(route);
            if (config == null || config.Batch_Size__c == null || config.Batch_Size__c < 1) return safeDefault;
            return config.Batch_Size__c.intValue();
        }

        public virtual Integer maxRetries(String route) {
            Event_Config__mdt config = getConfig(route);
            if (config == null || config.Max_Retries__c == null || config.Max_Retries__c < 1) return 0;
            return config.Max_Retries__c.intValue();
        }

        protected virtual List<Event_Config__mdt> loadConfigs() {
            return (List<Event_Config__mdt>) Query.records([
                SELECT DeveloperName, Active__c, Direction__c, Source_Type__c, Routing_Key__c, Routing_Value__c,
                    Apex__c, Batch_Size__c, Max_Retries__c, Idempotency_Key_Path__c
                FROM Event_Config__mdt
                WHERE Active__c = true
            ]);
        }
    }

    public virtual with sharing class RouteService {
        public virtual List<Route> forSObject(String payloadType) {
            return forSObject(payloadType, null);
        }

        public virtual List<Route> forSObject(String payloadType, String direction) {
            List<Route> resolvedRoutes = new List<Route>();
            for (Event_Config__mdt config : metadata.getConfigs()) {
                if (!matches(config, consts.PLATFORM_EVENT, consts.ROUTING_KEY_SOBJECT_TYPE, payloadType, direction)) continue;
                resolvedRoutes.add(toRoute(config, payloadType, direction));
            }
            return resolvedRoutes;
        }

        public virtual List<Route> forGeneric(Generic payload) {
            return forGeneric(payload, null);
        }

        public virtual List<Route> forGeneric(Generic payload, String direction) {
            List<Route> resolvedRoutes = new List<Route>();
            if (payload == null) return resolvedRoutes;

            for (Event_Config__mdt config : metadata.getConfigs()) {
                if (!matchesSourceAndDirection(config, consts.GENERIC_PAYLOAD, direction) || String.isBlank(config.Routing_Key__c)) {
                    continue;
                }

                String routingValue = (String) payload.get(config.Routing_Key__c, String.class);
                if (routingValue == config.Routing_Value__c) {
                    resolvedRoutes.add(toRoute(config, consts.GENERIC_PAYLOAD, direction));
                }
            }
            return resolvedRoutes;
        }

        public virtual String idempotencyKeyPathForSObject(String payloadType, String direction, String apexClass) {
            for (Event_Config__mdt config : metadata.getConfigs()) {
                if (!matches(config, consts.PLATFORM_EVENT, consts.ROUTING_KEY_SOBJECT_TYPE, payloadType, direction)) continue;
                if (matchesApex(config, consts.PLATFORM_EVENT, direction, apexClass)) return config.Idempotency_Key_Path__c;
            }
            return null;
        }

        public virtual String idempotencyKeyPathForGeneric(Generic payload, String direction, String apexClass) {
            if (payload == null) return null;

            for (Event_Config__mdt config : metadata.getConfigs()) {
                if (!matchesSourceAndDirection(config, consts.GENERIC_PAYLOAD, direction)
                    || String.isBlank(config.Routing_Key__c)
                    || !matchesApex(config, consts.GENERIC_PAYLOAD, direction, apexClass)) {
                    continue;
                }

                String routingValue = (String) payload.get(config.Routing_Key__c, String.class);
                if (routingValue == config.Routing_Value__c) return config.Idempotency_Key_Path__c;
            }
            return null;
        }

        Boolean matches(Event_Config__mdt config, String sourceType, String routingKey, String routingValue, String direction) {
            return matchesSourceAndDirection(config, sourceType, direction)
                && config.Routing_Key__c == routingKey
                && config.Routing_Value__c == routingValue;
        }

        Boolean matchesSourceAndDirection(Event_Config__mdt config, String sourceType, String direction) {
            if (config == null || config.Active__c != true) return false;
            if (config.Source_Type__c != sourceType) return false;
            if (String.isBlank(direction)) return true;
            return config.Direction__c == direction || config.Direction__c == consts.BOTH;
        }

        Boolean matchesApex(Event_Config__mdt config, String sourceType, String direction, String apexClass) {
            String configuredApex = config.Apex__c;
            if (sourceType == consts.PLATFORM_EVENT && direction == consts.PUBLISH && String.isBlank(configuredApex)) {
                configuredApex = consts.PLATFORM_EVENT_PUBLISHER;
            }
            return configuredApex == apexClass;
        }

        Route toRoute(Event_Config__mdt config, String payloadType, String direction) {
            String apexClass = config.Apex__c;
            if (direction == consts.PUBLISH && payloadType != consts.GENERIC_PAYLOAD && String.isBlank(apexClass)) {
                apexClass = consts.PLATFORM_EVENT_PUBLISHER;
            }
            if (String.isBlank(apexClass)) {
                throw new EventRelayException('Event_Config__mdt ' + config.DeveloperName + ' requires Apex__c.');
            }
            return new Route(config.DeveloperName, apexClass, payloadType, config.DeveloperName, config.Idempotency_Key_Path__c);
        }
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

        public Route(String route, String apexClass, String payloadType, String threadKey) {
            this(route, apexClass, payloadType, threadKey, null);
        }

        public Route(String route, String apexClass, String payloadType, String threadKey, String idempotencyKeyPath) {
            this.route = route;
            this.apexClass = apexClass;
            this.publisherClass = apexClass;
            this.payloadType = payloadType;
            this.threadKey = threadKey;
            this.idempotencyKeyPath = idempotencyKeyPath;
        }
    }

    static Route defaultPlatformEventRoute(String payloadType) {
        return new Route(
            payloadType,
            consts.PLATFORM_EVENT_PUBLISHER,
            payloadType,
            routeThreadKey(consts.PUBLISH, payloadType, payloadType)
        );
    }

    static String routeThreadKey(String jobType, String payloadType, String route) {
        return String.join(new List<String> {
            String.isBlank(jobType) ? consts.PUBLISH : jobType.trim(),
            String.isBlank(payloadType) ? consts.GENERIC_PAYLOAD : payloadType.trim(),
            String.isBlank(route) ? 'Default' : route.trim()
        }, ':');
    }

    static List<PublishResult> successResults(List<PublishPayload> publishPayloads) {
        List<PublishResult> results = new List<PublishResult>();
        if (publishPayloads == null) return results;

        for (PublishPayload publishPayload : publishPayloads) {
            results.add(new PublishResult(true, null));
        }
        return results;
    }

    static List<ProcessResult> successProcessResults(List<Generic> records) {
        List<ProcessResult> results = new List<ProcessResult>();
        if (records == null) return results;

        for (Generic record : records) {
            results.add(new ProcessResult(consts.DONE, null));
        }
        return results;
    }

    static void continueAfterJob(Id threadId, Set<Id> workItemIds, Integer failures, String runKey, FinalizerContext context) {
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

        public PublishPayload(Id workItemId, String route, String payloadType, Generic payload) {
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

        public PublishJob(Id threadId, List<Id> workItemIds, Integer failures, String runKey) {
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
            work.applyResults(workItems, publishers.forWorkItems(workItems).publish(payloads.toPublishPayloads(workItems)));
        }
    }

    public with sharing class ProcessJob implements Queueable, Database.AllowsCallouts {
        Id threadId;
        Integer failures;
        List<Id> workItemIds;
        String runKey;

        public ProcessJob(Id threadId, List<Id> workItemIds, Integer failures, String runKey) {
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
            jobs.attachFinalizer(jobs.watchProcess(threadId, workItemIds, failures, runKey));

            List<Event__c> workItems = queries.getWorkItemsById(workItemIds);
            work.applyProcessResults(workItems, handlers.forWorkItems(workItems).process(payloads.toGenericEvents(workItems)));
        }
    }

    public with sharing class PublishWatcher implements Finalizer {
        Id threadId;
        Integer failures;
        Set<Id> workItemIds;
        String runKey;

        public PublishWatcher(Id threadId, List<Id> workItemIds, Integer failures, String runKey) {
            this.threadId = threadId;
            this.workItemIds = workItemIds == null ? new Set<Id>() : new Set<Id>(workItemIds);
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

        public ProcessWatcher(Id threadId, List<Id> workItemIds, Integer failures, String runKey) {
            this.threadId = threadId;
            this.workItemIds = workItemIds == null ? new Set<Id>() : new Set<Id>(workItemIds);
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

        public override void dispatch(Id threadId, Integer failures, String runKey) {
            jobs.enqueueNextProcessJob(threadId, failures, runKey);
        }

        public override Boolean hasPendingWork(Id threadId) {
            return !queries.getPendingProcessWorkItems(threadId, 1).isEmpty();
        }

        public override Boolean hasRecoverableWork(Id threadId) {
            return hasPendingWork(threadId) || !queries.getRunningWorkItemIds(threadId, consts.PROCESS).isEmpty();
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

    public class EventRelayException extends Exception {}
}
