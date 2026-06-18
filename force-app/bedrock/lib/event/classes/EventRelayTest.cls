@istest
private class EventRelayTest {
    @istest static void publish_platformEvents_createsDurablePublishWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        MockWakeService wakeSignal = new MockWakeService();
        EventRelay.wakeSignal = wakeSignal;

        EventRelay.publish(new List<SObject> {
            new Bedrock_Test_Event__e(Message__c = 'created')
        });

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(1, insertedEvents.size(),
            'One platform event payload should create one Event__c work item.');

        Event__c workItem = insertedEvents[0];
        Assert.areEqual(EventRelay.PUBLISH, workItem.Job_Type__c,
            'Platform event publication should create publish work.');
        Assert.areEqual(EventRelay.PENDING, workItem.Status__c,
            'New EventRelay work should start as pending.');
        Assert.areEqual('Bedrock_Test_Event__e', workItem.Payload_Type__c,
            'The payload type should preserve the platform event API name.');
        Assert.areEqual('Publish:Bedrock_Test_Event__e:Bedrock_Test_Event__e', workItem.Thread_Key__c,
            'The publish lane should be keyed by job type, event type, and route.');
        Assert.isTrue(workItem.Payload1__c.contains('created'),
            'The serialized payload should carry populated platform event fields.');
        Assert.areEqual(1, wakeSignal.signalCalls,
            'Persisting EventRelay publish work should signal the wake event instead of directly starting work.');
    }

    @istest static void publish_sObjectPublisherType_createsDurablePublishWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        EventRelay.wakeSignal = new MockWakeService();

        EventRelay.publish(new List<SObject> {
            new Bedrock_Test_Event__e(Message__c = 'custom')
        }, MockSObjectPublisher.class);

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(1, insertedEvents.size(),
            'One SObject payload should create one Event__c work item for an explicit publisher.');

        Event__c workItem = insertedEvents[0];
        Assert.areEqual(MockSObjectPublisher.class.getName(), workItem.Apex__c,
            'Explicit SObject publisher work should store the publisher class name.');
        Assert.areEqual('Bedrock_Test_Event__e:' + MockSObjectPublisher.class.getName(), workItem.Route__c,
            'Explicit SObject publisher work should route by event type and publisher class.');
        Assert.areEqual('Bedrock_Test_Event__e', workItem.Payload_Type__c,
            'Explicit SObject publisher work should preserve the payload SObject type.');
        Assert.areEqual('Publish:Bedrock_Test_Event__e:Bedrock_Test_Event__e:' + MockSObjectPublisher.class.getName(), workItem.Thread_Key__c,
            'Explicit SObject publisher work should use a route-specific lane.');
    }

    @istest static void publish_sObjectMetadata_createsDurablePublishWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        EventRelay.wakeSignal = new MockWakeService();
        EventRelay.routes = new MockRouteService(new List<EventRelay.Route> {
            new EventRelay.Route(
                'Bedrock_Test_Event__e',
                MockSObjectPublisher.class.getName(),
                'Bedrock_Test_Event__e',
                'Publish:Bedrock_Test_Event__e:Bedrock_Test_Event__e'
            )
        });

        EventRelay.publish(new List<SObject> {
            new Bedrock_Test_Event__e(Message__c = 'metadata')
        });

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(1, insertedEvents.size(),
            'One SObject payload should create one Event__c work item from metadata routing.');

        Event__c workItem = insertedEvents[0];
        Assert.areEqual(MockSObjectPublisher.class.getName(), workItem.Apex__c,
            'SObject metadata routing should choose the configured publisher class.');
    }

    @istest static void publish_sObjectMetadata_fansOutToMultipleRouteLanes() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        EventRelay.wakeSignal = new MockWakeService();
        EventRelay.routes = new MockRouteService(new List<EventRelay.Route> {
            new EventRelay.Route(
                'Bedrock_Test_Event__e:Webhook',
                MockSObjectPublisher.class.getName(),
                'Bedrock_Test_Event__e',
                'Publish:Bedrock_Test_Event__e:Bedrock_Test_Event__e:Webhook'
            ),
            new EventRelay.Route(
                'Bedrock_Test_Event__e:Middleware',
                MockPublisher.class.getName(),
                'Bedrock_Test_Event__e',
                'Publish:Bedrock_Test_Event__e:Bedrock_Test_Event__e:Middleware'
            )
        });

        EventRelay.publish(new List<SObject> {
            new Bedrock_Test_Event__e(Message__c = 'fanout')
        });

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(2, insertedEvents.size(),
            'One source event should create one Event__c work item per resolved publish route.');

        Set<String> threadKeys = new Set<String>();
        for (Event__c workItem : insertedEvents) {
            threadKeys.add(workItem.Thread_Key__c);
        }
        Assert.isTrue(threadKeys.contains('Publish:Bedrock_Test_Event__e:Bedrock_Test_Event__e:Webhook'),
            'Fanout should create a route-specific lane for the webhook publisher.');
        Assert.isTrue(threadKeys.contains('Publish:Bedrock_Test_Event__e:Bedrock_Test_Event__e:Middleware'),
            'Fanout should create a route-specific lane for the middleware publisher.');
    }

    @istest static void publish_genericWithoutMetadata_throws() {
        EventRelay.reset();
        Boolean threwExpectedError = false;

        try {
            EventRelay.publish(new List<Generic> {
                new Generic(new Map<String, Object> { 'orderNumber' => '1001' })
            });
        } catch (EventRelay.EventRelayException error) {
            threwExpectedError = error.getMessage().contains('metadata');
        }

        Assert.isTrue(threwExpectedError,
            'Generic EventRelay publishing should require route metadata.');
    }

    @istest static void publish_genericMetadata_createsDurablePublishWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        EventRelay.wakeSignal = new MockWakeService();
        EventRelay.routes = new MockRouteService(new List<EventRelay.Route> {
            new EventRelay.Route(
                'Webhook:OrderService',
                MockGenericPublisher.class.getName(),
                EventRelay.GENERIC_PAYLOAD,
                'Publish:Generic:Webhook:OrderService'
            )
        });

        EventRelay.publish(new List<Generic> {
            new Generic(new Map<String, Object> {
                'orderNumber' => '1001',
                'status' => 'Ready'
            })
        });

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(1, insertedEvents.size(),
            'One generic payload should create one Event__c work item from metadata routing.');

        Event__c workItem = insertedEvents[0];
        Assert.areEqual(MockGenericPublisher.class.getName(), workItem.Apex__c,
            'Generic metadata routing should choose the configured publisher class.');
        Assert.areEqual('Webhook:OrderService', workItem.Route__c,
            'Generic metadata routing should store the configured route.');
        Assert.areEqual(EventRelay.GENERIC_PAYLOAD, workItem.Payload_Type__c,
            'Generic metadata routing should mark the payload as generic JSON.');
        Assert.areEqual('Publish:Generic:Webhook:OrderService', workItem.Thread_Key__c,
            'Generic metadata routing should use the configured route-specific lane key.');
        Assert.isTrue(workItem.Payload1__c.contains('1001'),
            'The stored generic payload should preserve JSON values.');
    }

    @istest static void publish_nonPlatformEvent_throws() {
        EventRelay.reset();
        Boolean threwExpectedError = false;

        try {
            EventRelay.publish(new List<SObject> { new Account(Name = 'Not an event') });
        } catch (EventRelay.EventRelayException error) {
            threwExpectedError = error.getMessage().contains('platform event');
        }

        Assert.isTrue(threwExpectedError,
            'EventRelay.publish should reject non-platform-event SObjects with a clear error.');
    }

    @istest static void flush_stagedEvents_createsWorkAndClearsBuffer() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        EventRelay.wakeSignal = new MockWakeService();

        EventRelay.stage(new List<SObject> {
            new Bedrock_Test_Event__e(Message__c = 'staged')
        });

        Assert.areEqual(0, eventInserts(dmlMock).size(),
            'Staging should not insert durable work before flush.');

        EventRelay.flush();
        EventRelay.flush();

        Assert.areEqual(1, eventInserts(dmlMock).size(),
            'The staged platform event should become one Event__c row.');
    }

    @istest static void payloadService_roundTripsPlatformEventPayload() {
        EventRelay.reset();
        EventRelay.PayloadService payloads = new EventRelay.PayloadService();
        Event__c workItem = new Event__c(Payload_Type__c = 'Bedrock_Test_Event__e');

        payloads.write(workItem, payloads.serialize(new Bedrock_Test_Event__e(Message__c = 'round trip')));

        Bedrock_Test_Event__e eventRecord = (Bedrock_Test_Event__e) payloads.toSObject(workItem);
        Assert.areEqual('round trip', eventRecord.Message__c,
            'Payload rehydration should rebuild the original platform event field values.');
    }

    @istest static void publishJob_updatesEachWorkItemFromPublisherResults() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        Id threadId = (Id) new TestData(Thread__c.sObjectType).mockIds().build()[0].Id;
        Event__c success = workItem('published');
        Event__c failure = workItem('failed');
        EventRelay.queries = new MockQueryService(new List<Event__c> { success, failure });
        MockPublisher publisher = new MockPublisher(new List<EventRelay.PublishResult> {
            new EventRelay.PublishResult(true, null),
            new EventRelay.PublishResult(false, 'publish failed')
        });
        EventRelay.publishers = new MockPublisherService(publisher);
        EventRelay.jobs = new MockJobService();

        new EventRelay.PublishJob(threadId, new List<Id> { success.Id, failure.Id }, 0, 'run').execute(null);

        Assert.areEqual(2, publisher.publishPayloads.size(),
            'The publish job should pass each pending work item to the publisher.');
        Assert.areEqual('published', publisher.publishPayloads[0].payload.get('Message__c', String.class),
            'The first published event should come from the first work item payload.');
        Assert.areEqual('failed', publisher.publishPayloads[1].payload.get('Message__c', String.class),
            'The second published event should preserve the selected FIFO order.');
        Assert.areEqual(1, dmlMock.updates.size(),
            'Publisher results should be written in a single DML update call.');

        Map<Id, Event__c> updatesById = new Map<Id, Event__c>();
        for (SObject updateRecord : dmlMock.updates[0]) {
            updatesById.put(updateRecord.Id, (Event__c) updateRecord);
        }
        Assert.areEqual(EventRelay.DONE, updatesById.get(success.Id).Status__c,
            'Successful publish results should mark the work item done.');
        Assert.areEqual(EventRelay.ERROR, updatesById.get(failure.Id).Status__c,
            'Failed publish results should mark the work item errored.');
        Assert.areEqual('publish failed', updatesById.get(failure.Id).Error_Message__c,
            'Failed publish results should preserve the publisher error message.');
    }

    @istest static void publisherService_requiresPlatformEventLimitOnlyForBuiltInPublisher() {
        EventRelay.PublisherService publishers = new EventRelay.PublisherService();

        Assert.isTrue(publishers.requiresPlatformEventLimit(new List<Event__c> {
            new Event__c(Apex__c = EventRelay.PLATFORM_EVENT_PUBLISHER)
        }), 'The built-in Platform Event publisher should check Platform Event publish limits.');

        Assert.isFalse(publishers.requiresPlatformEventLimit(new List<Event__c> {
            new Event__c(Apex__c = MockPublisher.class.getName())
        }), 'Custom publishers should not be blocked by Platform Event publish limits.');
    }

    @istest static void genericPublisher_executeCompletesPayloadsAsSuccessfulResults() {
        MockGenericPublisher publisher = new MockGenericPublisher();
        List<EventRelay.PublishResult> results = publisher.publish(new List<EventRelay.PublishPayload> {
            new EventRelay.PublishPayload(null, 'Webhook:OrderService', EventRelay.GENERIC_PAYLOAD,
                new Generic(new Map<String, Object> { 'orderNumber' => '1001' }))
        });

        Assert.areEqual(1, publisher.executedPayloads.size(),
            'GenericPublisher should pass generic payloads to execute.');
        Assert.areEqual('1001', publisher.executedPayloads[0].get('orderNumber', String.class),
            'GenericPublisher should preserve the generic payload values.');
        Assert.areEqual(1, results.size(),
            'GenericPublisher should return one result per executed payload.');
        Assert.isTrue(results[0].success,
            'GenericPublisher should mark payloads successful when execute completes.');
    }

    @istest static void genericPublisher_canFailSpecificRecord() {
        FailingGenericPublisher publisher = new FailingGenericPublisher();

        List<EventRelay.PublishResult> results = publisher.publish(new List<EventRelay.PublishPayload> {
            new EventRelay.PublishPayload(null, 'Webhook:OrderService', EventRelay.GENERIC_PAYLOAD,
                new Generic(new Map<String, Object> { 'orderNumber' => '1001' })),
            new EventRelay.PublishPayload(null, 'Webhook:OrderService', EventRelay.GENERIC_PAYLOAD,
                new Generic(new Map<String, Object> { 'orderNumber' => '1002' }))
        });

        Assert.areEqual(2, results.size(),
            'GenericPublisher should return one result per payload after item-level failure handling.');
        Assert.isTrue(results[0].success,
            'GenericPublisher should leave unfailed records successful.');
        Assert.isFalse(results[1].success,
            'GenericPublisher should fail only the record passed to fail.');
        Assert.areEqual('rejected', results[1].message,
            'GenericPublisher should preserve the item-level failure message.');
    }

    @istest static void sObjectPublisher_executeCompletesPayloadsAsSuccessfulResults() {
        MockSObjectPublisher publisher = new MockSObjectPublisher();
        List<EventRelay.PublishResult> results = publisher.publish(new List<EventRelay.PublishPayload> {
            new EventRelay.PublishPayload(null, 'Bedrock_Test_Event__e', 'Bedrock_Test_Event__e',
                new Generic(new Map<String, Object> { 'Message__c' => 'published' }))
        });

        Assert.areEqual(1, publisher.executedRecords.size(),
            'SObjectPublisher should pass SObject records to execute.');
        Assert.areEqual('published', ((Bedrock_Test_Event__e) publisher.executedRecords[0]).Message__c,
            'SObjectPublisher should rehydrate typed SObject payload values.');
        Assert.areEqual(1, results.size(),
            'SObjectPublisher should return one result per executed payload.');
        Assert.isTrue(results[0].success,
            'SObjectPublisher should mark payloads successful when execute completes.');
    }

    @istest static void sObjectPublisher_canFailSpecificRecord() {
        FailingSObjectPublisher publisher = new FailingSObjectPublisher();

        List<EventRelay.PublishResult> results = publisher.publish(new List<EventRelay.PublishPayload> {
            new EventRelay.PublishPayload(null, 'Bedrock_Test_Event__e', 'Bedrock_Test_Event__e',
                new Generic(new Map<String, Object> { 'Message__c' => 'accepted' })),
            new EventRelay.PublishPayload(null, 'Bedrock_Test_Event__e', 'Bedrock_Test_Event__e',
                new Generic(new Map<String, Object> { 'Message__c' => 'rejected' }))
        });

        Assert.areEqual(2, results.size(),
            'SObjectPublisher should return one result per payload after item-level failure handling.');
        Assert.isTrue(results[0].success,
            'SObjectPublisher should leave unfailed records successful.');
        Assert.isFalse(results[1].success,
            'SObjectPublisher should fail only the record passed to fail.');
        Assert.areEqual('rejected', results[1].message,
            'SObjectPublisher should preserve the item-level failure message.');
    }

    static Event__c workItem(String message) {
        EventRelay.PayloadService payloads = new EventRelay.PayloadService();
        Event__c workItem = (Event__c) new TestData(Event__c.sObjectType)
            .mockIds()
            .build()[0];
        workItem.Apex__c = EventRelay.PLATFORM_EVENT_PUBLISHER;
        workItem.Route__c = 'Bedrock_Test_Event__e';
        workItem.Payload_Type__c = 'Bedrock_Test_Event__e';
        payloads.write(workItem, payloads.serialize(new Bedrock_Test_Event__e(Message__c = message)));
        return workItem;
    }

    static List<Event__c> eventInserts(DMLMock dmlMock) {
        List<Event__c> events = new List<Event__c>();
        for (List<SObject> insertCall : dmlMock.inserts) {
            for (SObject record : insertCall) {
                if (record instanceof Event__c) {
                    events.add((Event__c) record);
                }
            }
        }
        return events;
    }

    private class MockQueryService extends EventRelay.QueryService {
        List<Event__c> workItems;

        MockQueryService(List<Event__c> workItems) {
            this.workItems = workItems;
        }

        public override List<Event__c> getWorkItemsById(List<Id> workItemIds) {
            return workItems;
        }
    }

    private class MockPublisherService extends EventRelay.PublisherService {
        EventRelay.Publisher publisher;

        MockPublisherService(EventRelay.Publisher publisher) {
            this.publisher = publisher;
        }

        public override EventRelay.Publisher forWorkItems(List<Event__c> workItems) {
            return publisher;
        }
    }

    private class MockRouteService extends EventRelay.RouteService {
        List<EventRelay.Route> routes;

        MockRouteService(List<EventRelay.Route> routes) {
            this.routes = routes;
        }

        public override List<EventRelay.Route> forSObject(String payloadType) {
            return routes;
        }

        public override List<EventRelay.Route> forGeneric(Generic payload) {
            return routes;
        }
    }

    private class MockWakeService extends EventRelay.WakeService {
        Integer signalCalls = 0;

        public override void signal() {
            signalCalls++;
        }
    }

    private class MockPublisher extends EventRelay.Publisher {
        List<EventRelay.PublishPayload> publishPayloads = new List<EventRelay.PublishPayload>();
        List<EventRelay.PublishResult> results;

        MockPublisher() {
            this(new List<EventRelay.PublishResult>());
        }

        MockPublisher(List<EventRelay.PublishResult> results) {
            this.results = results;
        }

        public override List<EventRelay.PublishResult> publish(List<EventRelay.PublishPayload> publishPayloads) {
            this.publishPayloads = publishPayloads;
            return results;
        }
    }

    private class MockGenericPublisher extends EventRelay.Publisher {
        List<Generic> executedPayloads = new List<Generic>();

        public override void execute(List<Generic> records) {
            this.executedPayloads = records;
        }
    }

    private class FailingGenericPublisher extends EventRelay.Publisher {
        public override void execute(List<Generic> records) {
            fail(records[1], 'rejected');
        }
    }

    private class MockSObjectPublisher extends EventRelay.Publisher {
        List<SObject> executedRecords = new List<SObject>();

        public override void execute(List<SObject> records) {
            this.executedRecords = records;
        }
    }

    private class FailingSObjectPublisher extends EventRelay.Publisher {
        public override void execute(List<SObject> records) {
            fail(records[1], 'rejected');
        }
    }

    private class MockJobService extends EventRelay.JobService {
        public override void attachFinalizer(Finalizer finalizer) {
        }
    }
}
