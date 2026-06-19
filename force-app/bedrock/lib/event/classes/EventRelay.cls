public virtual with sharing class EventRelay {
    public static final String PUBLISH_POOL = 'EventRelayPublish';
    public static final String PROCESS_POOL = 'EventRelayProcess';
    public static final String PLATFORM_EVENT_PUBLISHER = PlatformEventPublisher.class.getName();
    public static final String GENERIC_PAYLOAD = 'Generic';
    public static final String PUBLISH = 'Publish';
    public static final String PROCESS = 'Process';
    public static final String PENDING = 'Pending';
    public static final String RUNNING = 'Running';
    public static final String PAUSED = 'Paused';
    public static final String DONE = 'Done';
    public static final String ERROR = 'Error';

    public static JobService jobs = new JobService();
    public static WorkService work = new WorkService();
    public static QueryService queries = new QueryService();
    public static PayloadService payloads = new PayloadService();
    public static HandlerService handlers = new HandlerService();
    public static PublisherService publishers = new PublisherService();
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
        routes = new RouteService();
        settings = new SettingsService();
        wakeSignal = new WakeService();
        Thread.reset();
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

    public static void wake() {
        if (!Thread.service.canEnqueue() || Thread.service.hasEnqueued || System.isQueueable() || Thread.service.isFinalizer) return;

        Thread.service.fillAvailableSlots(PUBLISH_POOL);
        Thread.service.fillAvailableSlots(PROCESS_POOL);
    }

    public static void stage(List<SObject> events) {
        work.stage(events);
    }

    public static List<Id> flush() {
        return work.flush();
    }

    public static Boolean isEventPool(String pool) {
        String normalizedPool = String.isBlank(pool) ? '' : pool.trim();
        return normalizedPool == PUBLISH_POOL || normalizedPool == PROCESS_POOL;
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

            DML.insertRecords(workItems);
            Thread.reopen(threadIdsFrom(workItems));
            jobs.enqueue(workItems);
            return idsFrom(workItems);
        }

        public virtual List<Event__c> newWorkItems(List<SObject> events, Type publisherType) {
            List<Event__c> workItems = new List<Event__c>();
            if (events == null || events.isEmpty()) return workItems;

            Integer order = 0;
            for (SObject eventRecord : events) {
                String eventType = eventType(eventRecord);
                for (Route route : sObjectRoutes(eventType, publisherType)) {
                    Id threadId = Thread.currentOrCreate(PUBLISH_POOL, route.threadKey);
                    Event__c workItem = new Event__c(
                        Apex__c = route.publisherClass,
                        Job_Type__c = PUBLISH,
                        Status__c = PENDING,
                        Route__c = route.route,
                        Payload_Type__c = route.payloadType,
                        Thread__c = threadId,
                        Thread_Key__c = route.threadKey,
                        Order__c = order,
                        Retry_Count__c = 0
                    );
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

                List<Route> resolvedRoutes = routes.forGeneric(payload);
                if (resolvedRoutes == null || resolvedRoutes.isEmpty()) {
                    throw new EventRelayException('EventRelay.publish requires route metadata for generic payloads.');
                }

                for (Route route : resolvedRoutes) {
                    Id threadId = Thread.currentOrCreate(PUBLISH_POOL, route.threadKey);
                    Event__c workItem = new Event__c(
                        Apex__c = route.publisherClass,
                        Job_Type__c = PUBLISH,
                        Status__c = PENDING,
                        Route__c = route.route,
                        Payload_Type__c = GENERIC_PAYLOAD,
                        Thread__c = threadId,
                        Thread_Key__c = route.threadKey,
                        Order__c = order,
                        Retry_Count__c = 0
                    );
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
                    Id threadId = Thread.currentOrCreate(PROCESS_POOL, route.threadKey);
                    Event__c workItem = new Event__c(
                        Apex__c = route.publisherClass,
                        Job_Type__c = PROCESS,
                        Status__c = PENDING,
                        Route__c = route.route,
                        Payload_Type__c = route.payloadType,
                        Thread__c = threadId,
                        Thread_Key__c = route.threadKey,
                        Order__c = order,
                        Retry_Count__c = 0
                    );
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
                    Id threadId = Thread.currentOrCreate(PROCESS_POOL, route.threadKey);
                    Event__c workItem = new Event__c(
                        Apex__c = route.publisherClass,
                        Job_Type__c = PROCESS,
                        Status__c = PENDING,
                        Route__c = route.route,
                        Payload_Type__c = GENERIC_PAYLOAD,
                        Thread__c = threadId,
                        Thread_Key__c = route.threadKey,
                        Order__c = order,
                        Retry_Count__c = 0
                    );
                    payloads.write(workItem, payload.json());
                    workItems.add(workItem);
                    order++;
                }
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
            prepareRecovery(threadId, PUBLISH);
        }

        public virtual void prepareRecovery(Id threadId, String jobType) {
            updateStatus(queries.getRunningWorkItemIds(threadId, jobType), new Event__c(Status__c = PENDING));
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
                return new List<Route> {
                    new Route(route, publisherClass(publisherType), eventType, routeThreadKey(PUBLISH, eventType, route))
                };
            }

            List<Route> resolvedRoutes = routes.forSObject(eventType);
            return resolvedRoutes == null || resolvedRoutes.isEmpty()
                ? new List<Route> { defaultPlatformEventRoute(eventType) }
                : resolvedRoutes;
        }

        List<Route> sObjectProcessRoutes(String eventType, Type handlerType) {
            if (handlerType != null) {
                String route = eventType + ':' + handlerType.getName();
                return new List<Route> {
                    new Route(route, handlerClass(handlerType), eventType, routeThreadKey(PROCESS, eventType, route))
                };
            }

            List<Route> resolvedRoutes = routes.forSObject(eventType);
            if (resolvedRoutes == null || resolvedRoutes.isEmpty()) {
                throw new EventRelayException('EventRelay.ingest requires route metadata or an explicit handler class.');
            }
            return resolvedRoutes;
        }

        List<Route> genericProcessRoutes(Generic payload, Type handlerType) {
            if (handlerType != null) {
                String route = GENERIC_PAYLOAD + ':' + handlerType.getName();
                return new List<Route> {
                    new Route(route, handlerClass(handlerType), GENERIC_PAYLOAD, routeThreadKey(PROCESS, GENERIC_PAYLOAD, route))
                };
            }

            List<Route> resolvedRoutes = routes.forGeneric(payload);
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
            List<Event__c> workItems = queries.getPendingWorkItems(threadId, settings.batchSize());
            if (workItems.isEmpty()) {
                Thread.continueCurrent(failures, runKey);
                return;
            }

            List<Id> workItemIds = idsFrom(workItems);
            if (publishers.requiresPlatformEventLimit(workItems)
                && !Limiter.isSafe(Limiter.types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS, settings.limitThresholdPct())) {
                work.pause(new Set<Id>(workItemIds), 'Platform Event publication limit is not safe.');
                Thread.continueCurrent(failures, runKey);
                return;
            }

            work.running(new Set<Id>(workItemIds));
            new PublishJob(threadId, workItemIds, failures, runKey).enqueue();
        }

        public virtual void enqueueNextProcessJob(Id threadId, Integer failures) {
            enqueueNextProcessJob(threadId, failures, Thread.service.currentRunKey(threadId));
        }

        public virtual void enqueueNextProcessJob(Id threadId, Integer failures, String runKey) {
            List<Event__c> workItems = queries.getPendingProcessWorkItems(threadId, settings.batchSize());
            if (workItems.isEmpty()) {
                Thread.continueCurrent(failures, runKey);
                return;
            }

            List<Id> workItemIds = idsFrom(workItems);
            work.running(new Set<Id>(workItemIds));
            new ProcessJob(threadId, workItemIds, failures, runKey).enqueue();
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
            return getPendingWorkItems(threadId, batchSize, PUBLISH);
        }

        public virtual List<Event__c> getPendingProcessWorkItems(Id threadId, Integer batchSize) {
            return getPendingWorkItems(threadId, batchSize, PROCESS);
        }

        public virtual List<Event__c> getPendingWorkItems(Id threadId, Integer batchSize, String jobType) {
            Integer safeBatchSize = batchSize == null || batchSize < 1 ? settings.batchSize() : batchSize;
            String safeJobType = String.isBlank(jobType) ? PUBLISH : jobType.trim();
            List<Event__c> workItems = (List<Event__c>) Query.records(Database.query(
                'SELECT Id, Payload_Type__c, Payload1__c, Payload2__c, Payload3__c, Payload4__c ' +
                    ', Apex__c, Route__c ' +
                'FROM Event__c ' +
                'WHERE Thread__c = :threadId ' +
                    'AND Job_Type__c = :safeJobType ' +
                    'AND Status__c = \'Pending\' ' +
                'ORDER BY CreatedDate ASC, Order__c ASC, Name ASC ' +
                'LIMIT :safeBatchSize'
            ));
            return strictContiguous(workItems);
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
            return getRunningWorkItemIds(threadId, PUBLISH);
        }

        public virtual Set<Id> getRunningWorkItemIds(Id threadId, String jobType) {
            Set<Id> workItemIds = new Set<Id>();
            String safeJobType = String.isBlank(jobType) ? PUBLISH : jobType.trim();
            for (Event__c workItem : (List<Event__c>) Query.records([
                SELECT Id
                FROM Event__c
                WHERE Thread__c = :threadId
                    AND Job_Type__c = :safeJobType
                    AND Status__c = 'Running'
            ])) {
                workItemIds.add(workItem.Id);
            }
            return workItemIds;
        }

        public virtual List<Event__c> getWorkItemsById(List<Id> workItemIds) {
            if (workItemIds == null || workItemIds.isEmpty()) return new List<Event__c>();

            Map<Id, Event__c> workItemsById = new Map<Id, Event__c>((List<Event__c>) Query.records([
                SELECT Id, Apex__c, Route__c, Payload_Type__c, Payload1__c, Payload2__c, Payload3__c, Payload4__c
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

        List<Event__c> strictContiguous(List<Event__c> workItems) {
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
        public virtual void execute(List<Generic> records) {
            throw new EventRelayException('Handler must override execute(List<Generic>).');
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
                && publishPayloads[0].payloadType == GENERIC_PAYLOAD;
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
            return String.isBlank(publisherClass) || publisherClass == PLATFORM_EVENT_PUBLISHER;
        }

        public virtual Publisher forClass(String publisherClass) {
            String safePublisherClass = String.isBlank(publisherClass)
                ? PLATFORM_EVENT_PUBLISHER
                : publisherClass.trim();
            if (safePublisherClass == PLATFORM_EVENT_PUBLISHER) {
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

    public virtual with sharing class RouteService {
        public virtual List<Route> forSObject(String payloadType) {
            return new List<Route>();
        }

        public virtual List<Route> forGeneric(Generic payload) {
            return new List<Route>();
        }
    }

    public virtual with sharing class WakeService {
        public virtual void signal() {
            EventBus.publish(new EventRelay_Wake__e());
        }
    }

    public with sharing class Route {
        public String route;
        public String publisherClass;
        public String payloadType;
        public String threadKey;

        public Route(String route, String publisherClass, String payloadType, String threadKey) {
            this.route = route;
            this.publisherClass = publisherClass;
            this.payloadType = payloadType;
            this.threadKey = threadKey;
        }
    }

    static Route defaultPlatformEventRoute(String payloadType) {
        return new Route(
            payloadType,
            PLATFORM_EVENT_PUBLISHER,
            payloadType,
            routeThreadKey(PUBLISH, payloadType, payloadType)
        );
    }

    static String routeThreadKey(String jobType, String payloadType, String route) {
        return String.join(new List<String> {
            String.isBlank(jobType) ? PUBLISH : jobType.trim(),
            String.isBlank(payloadType) ? GENERIC_PAYLOAD : payloadType.trim(),
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
            handlers.forWorkItems(workItems).execute(payloads.toGenericEvents(workItems));
            work.complete(new Set<Id>(workItemIds));
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
            return hasPendingWork(threadId) || !queries.getRunningWorkItemIds(threadId, PROCESS).isEmpty();
        }

        public override void prepareRecovery(Id threadId) {
            work.prepareRecovery(threadId, PROCESS);
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
