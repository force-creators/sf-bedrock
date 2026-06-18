@istest
private class EventRelayTest {
    @istest static void publish_platformEvents_createsDurablePublishWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());

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
        Assert.areEqual('Bedrock_Test_Event__e', workItem.Thread_Key__c,
            'The publish lane should be keyed by platform event type.');
        Assert.isTrue(workItem.Payload1__c.contains('created'),
            'The serialized payload should carry populated platform event fields.');
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
        EventRelay.publisher = publisher;
        EventRelay.jobs = new MockJobService();

        new EventRelay.PublishJob(threadId, new Set<Id> { success.Id, failure.Id }, 0, 'run').execute(null);

        Assert.areEqual(2, publisher.events.size(),
            'The publish job should pass each pending work item to the publisher.');
        Assert.areEqual('published', ((Bedrock_Test_Event__e) publisher.events[0]).Message__c,
            'The first published event should come from the first work item payload.');
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

    static Event__c workItem(String message) {
        EventRelay.PayloadService payloads = new EventRelay.PayloadService();
        Event__c workItem = (Event__c) new TestData(Event__c.sObjectType)
            .mockIds()
            .build()[0];
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

        public override List<Event__c> getWorkItemsById(Set<Id> workItemIds) {
            return workItems;
        }
    }

    private class MockPublisher extends EventRelay.Publisher {
        List<SObject> events = new List<SObject>();
        List<EventRelay.PublishResult> results;

        MockPublisher(List<EventRelay.PublishResult> results) {
            this.results = results;
        }

        public override List<EventRelay.PublishResult> publish(List<SObject> events) {
            this.events = events;
            return results;
        }
    }

    private class MockJobService extends EventRelay.JobService {
        public override void attachFinalizer(Finalizer finalizer) {
        }
    }
}
