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

    @istest static void publish_sObjectConfig_createsDurablePublishWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        EventRelay.wakeSignal = new MockWakeService();
        EventRelay.metadata = new MockMetadataService(new List<Event_Config__mdt> {
            eventConfig(
                'BedrockTestPublish',
                EventRelay.PUBLISH,
                EventRelay.PLATFORM_EVENT,
                EventRelay.ROUTING_KEY_SOBJECT_TYPE,
                'Bedrock_Test_Event__e',
                MockSObjectPublisher.class.getName(),
                25
            )
        });

        EventRelay.publish(new List<SObject> {
            new Bedrock_Test_Event__e(Message__c = 'configured')
        });

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(1, insertedEvents.size(),
            'One platform event should create one Event__c work item from Event_Config__mdt.');

        Event__c workItem = insertedEvents[0];
        Assert.areEqual('BedrockTestPublish', workItem.Route__c,
            'Configured routes should store the Event_Config__mdt DeveloperName as the route.');
        Assert.areEqual('BedrockTestPublish', workItem.Thread_Key__c,
            'Configured routes should use the Event_Config__mdt DeveloperName as the thread key.');
        Assert.areEqual(MockSObjectPublisher.class.getName(), workItem.Apex__c,
            'Configured platform event publish routes should use Apex__c as the publisher class.');
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
            'Generic metadata routing should mark the payload as generic.');
        Assert.areEqual('Publish:Generic:Webhook:OrderService', workItem.Thread_Key__c,
            'Generic metadata routing should use the configured route-specific lane key.');
        Assert.isTrue(workItem.Payload1__c.contains('1001'),
            'The stored generic payload should preserve payload values.');
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

    @istest static void ingest_platformEventsWithHandler_createsDurableProcessWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        MockWakeService wakeSignal = new MockWakeService();
        EventRelay.wakeSignal = wakeSignal;

        EventRelay.ingest(new List<SObject> {
            new Bedrock_Test_Event__e(Message__c = 'received')
        }, MockHandler.class);

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(1, insertedEvents.size(),
            'One ingested platform event should create one Event__c process work item.');

        Event__c workItem = insertedEvents[0];
        Assert.areEqual(EventRelay.PROCESS, workItem.Job_Type__c,
            'Platform event ingestion should create process work.');
        Assert.areEqual(EventRelay.PENDING, workItem.Status__c,
            'New EventRelay process work should start as pending.');
        Assert.areEqual(MockHandler.class.getName(), workItem.Apex__c,
            'Process work should store the handler class name.');
        Assert.areEqual('Bedrock_Test_Event__e', workItem.Payload_Type__c,
            'Process work should preserve the platform event API name.');
        Assert.areEqual('Process:Bedrock_Test_Event__e:Bedrock_Test_Event__e:' + MockHandler.class.getName(), workItem.Thread_Key__c,
            'Process work should use a handler-specific process lane.');
        Assert.isTrue(workItem.Payload1__c.contains('received'),
            'The serialized process payload should carry populated platform event fields.');
        Assert.areEqual(1, wakeSignal.signalCalls,
            'Persisting EventRelay process work should signal the wake event.');
    }

    @istest static void ingest_genericWithHandler_createsDurableProcessWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        EventRelay.wakeSignal = new MockWakeService();

        EventRelay.ingest(new List<Generic> {
            new Generic(new Map<String, Object> {
                'orderNumber' => '1001',
                'status' => 'Ready'
            })
        }, MockHandler.class);

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(1, insertedEvents.size(),
            'One generic payload should create one Event__c process work item.');

        Event__c workItem = insertedEvents[0];
        Assert.areEqual(EventRelay.PROCESS, workItem.Job_Type__c,
            'Generic ingestion should create process work.');
        Assert.areEqual(MockHandler.class.getName(), workItem.Apex__c,
            'Generic process work should store the handler class name.');
        Assert.areEqual(EventRelay.GENERIC_PAYLOAD, workItem.Payload_Type__c,
            'Generic process work should mark the payload as generic.');
        Assert.areEqual('Process:Generic:Generic:' + MockHandler.class.getName(), workItem.Thread_Key__c,
            'Generic process work should use a handler-specific process lane.');
        Assert.isTrue(workItem.Payload1__c.contains('1001'),
            'The stored generic process payload should preserve payload values.');
    }

    @istest static void ingest_genericConfig_createsDurableProcessWork() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Thread.setMock(new ThreadMock().mockIds());
        EventRelay.wakeSignal = new MockWakeService();
        EventRelay.metadata = new MockMetadataService(new List<Event_Config__mdt> {
            eventConfig(
                'OrderSubmittedProcess',
                EventRelay.INGEST,
                EventRelay.GENERIC_PAYLOAD,
                'EventType',
                'OrderSubmitted',
                MockHandler.class.getName(),
                10
            )
        });

        EventRelay.ingest(new List<Generic> {
            new Generic(new Map<String, Object> {
                'EventType' => 'OrderSubmitted',
                'orderNumber' => '1001'
            })
        });

        List<Event__c> insertedEvents = eventInserts(dmlMock);
        Assert.areEqual(1, insertedEvents.size(),
            'One generic payload should create one Event__c process work item from Event_Config__mdt.');

        Event__c workItem = insertedEvents[0];
        Assert.areEqual(EventRelay.PROCESS, workItem.Job_Type__c,
            'Configured generic ingestion should create process work.');
        Assert.areEqual('OrderSubmittedProcess', workItem.Route__c,
            'Configured generic routes should store the Event_Config__mdt DeveloperName as the route.');
        Assert.areEqual('OrderSubmittedProcess', workItem.Thread_Key__c,
            'Configured generic routes should use the Event_Config__mdt DeveloperName as the thread key.');
        Assert.areEqual(MockHandler.class.getName(), workItem.Apex__c,
            'Configured generic process routes should use Apex__c as the handler class.');
    }

    @istest static void metadataService_batchSize_usesConfiguredRouteBatchSize() {
        EventRelay.reset();
        EventRelay.metadata = new MockMetadataService(new List<Event_Config__mdt> {
            eventConfig(
                'OrderSubmittedProcess',
                EventRelay.INGEST,
                EventRelay.GENERIC_PAYLOAD,
                'EventType',
                'OrderSubmitted',
                MockHandler.class.getName(),
                17
            )
        });

        Assert.areEqual(17, EventRelay.metadata.batchSize('OrderSubmittedProcess', 50),
            'EventRelay should use Event_Config__mdt Batch_Size__c for configured routes.');
        Assert.areEqual(50, EventRelay.metadata.batchSize('MissingRoute', 50),
            'EventRelay should fall back to the provided batch size when no config route exists.');
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

    @istest static void publishJob_retriesFailedResultUntilConfiguredCap() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        Id threadId = (Id) new TestData(Thread__c.sObjectType).mockIds().build()[0].Id;
        Event__c retryable = workItem('retryable');
        Event__c terminal = workItem('terminal');
        terminal.Retry_Count__c = 2;
        Event_Config__mdt config = eventConfig(
            retryable.Route__c,
            EventRelay.PUBLISH,
            EventRelay.PLATFORM_EVENT,
            EventRelay.ROUTING_KEY_SOBJECT_TYPE,
            retryable.Payload_Type__c,
            EventRelay.PLATFORM_EVENT_PUBLISHER,
            null
        );
        config.Max_Retries__c = 2;
        EventRelay.metadata = new MockMetadataService(new List<Event_Config__mdt> { config });
        EventRelay.queries = new MockQueryService(new List<Event__c> { retryable, terminal });
        EventRelay.publishers = new MockPublisherService(new MockPublisher(new List<EventRelay.PublishResult> {
            new EventRelay.PublishResult(false, 'retryable failure'),
            new EventRelay.PublishResult(false, 'terminal failure')
        }));
        EventRelay.jobs = new MockJobService();

        new EventRelay.PublishJob(threadId, new List<Id> { retryable.Id, terminal.Id }, 0, 'run').execute(null);

        Map<Id, Event__c> updatesById = new Map<Id, Event__c>();
        for (SObject updateRecord : dmlMock.updates[0]) {
            updatesById.put(updateRecord.Id, (Event__c) updateRecord);
        }
        Assert.areEqual(EventRelay.PENDING, updatesById.get(retryable.Id).Status__c,
            'Failed publish work below the configured retry cap should move back to pending.');
        Assert.areEqual(1, updatesById.get(retryable.Id).Retry_Count__c,
            'Failed publish work below the configured retry cap should increment retry count.');
        Assert.areEqual('retryable failure', updatesById.get(retryable.Id).Error_Message__c,
            'Retried publish work should preserve the latest publisher error message.');
        Assert.areEqual(EventRelay.ERROR, updatesById.get(terminal.Id).Status__c,
            'Failed publish work at the configured retry cap should become terminal error work.');
        Assert.areEqual(null, updatesById.get(terminal.Id).Retry_Count__c,
            'Terminal publish work should not increment retry count beyond the configured cap.');
        Assert.areEqual('terminal failure', updatesById.get(terminal.Id).Error_Message__c,
            'Terminal publish work should preserve the latest publisher error message.');
    }

    @istest static void processJob_executesHandlerAndCompletesWorkItems() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        Id threadId = (Id) new TestData(Thread__c.sObjectType).mockIds().build()[0].Id;
        Event__c first = processWorkItem('1001');
        Event__c second = processWorkItem('1002');
        EventRelay.queries = new MockQueryService(new List<Event__c> { first, second });
        MockHandler handler = new MockHandler();
        EventRelay.handlers = new MockHandlerService(handler);
        EventRelay.jobs = new MockJobService();

        new EventRelay.ProcessJob(threadId, new List<Id> { first.Id, second.Id }, 0, 'run').execute(null);

        Assert.areEqual(2, handler.records.size(),
            'The process job should pass every selected work item payload to the handler.');
        Assert.areEqual('1001', handler.records[0].get('orderNumber', String.class),
            'The first handled payload should come from the first process work item.');
        Assert.areEqual('1002', handler.records[1].get('orderNumber', String.class),
            'The second handled payload should preserve selected FIFO order.');
        Assert.areEqual(1, dmlMock.updates.size(),
            'Successful handler execution should update process work in one DML call.');

        Map<Id, Event__c> updatesById = new Map<Id, Event__c>();
        for (SObject updateRecord : dmlMock.updates[0]) {
            updatesById.put(updateRecord.Id, (Event__c) updateRecord);
        }
        Assert.areEqual(EventRelay.DONE, updatesById.get(first.Id).Status__c,
            'Successful handler execution should mark the first work item done.');
        Assert.areEqual(EventRelay.DONE, updatesById.get(second.Id).Status__c,
            'Successful handler execution should mark the second work item done.');
    }

    @istest static void processJob_appliesExplicitHandlerFailures() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        Id threadId = (Id) new TestData(Thread__c.sObjectType).mockIds().build()[0].Id;
        Event__c explicitCompleted = processWorkItem('1001');
        Event__c failed = processWorkItem('1002');
        Event__c defaultCompleted = processWorkItem('1003');
        Event_Config__mdt config = eventConfig(
            explicitCompleted.Route__c,
            EventRelay.INGEST,
            EventRelay.GENERIC_PAYLOAD,
            'type',
            'order',
            PartialResultHandler.class.getName(),
            null
        );
        config.Max_Retries__c = 1;
        EventRelay.metadata = new MockMetadataService(new List<Event_Config__mdt> { config });
        EventRelay.queries = new MockQueryService(new List<Event__c> { explicitCompleted, failed, defaultCompleted });
        PartialResultHandler handler = new PartialResultHandler();
        EventRelay.handlers = new MockHandlerService(handler);
        EventRelay.jobs = new MockJobService();

        new EventRelay.ProcessJob(threadId, new List<Id> {
            explicitCompleted.Id,
            failed.Id,
            defaultCompleted.Id
        }, 0, 'run').execute(null);

        Assert.areEqual(3, handler.records.size(),
            'The process job should pass every selected work item payload to the handler.');
        Map<Id, Event__c> updatesById = new Map<Id, Event__c>();
        for (SObject updateRecord : dmlMock.updates[0]) {
            updatesById.put(updateRecord.Id, (Event__c) updateRecord);
        }
        Assert.areEqual(EventRelay.DONE, updatesById.get(explicitCompleted.Id).Status__c,
            'An explicitly completed handler record should be marked done.');
        Assert.areEqual(EventRelay.PENDING, updatesById.get(failed.Id).Status__c,
            'A handler-failed record below the configured retry cap should move back to pending.');
        Assert.areEqual(1, updatesById.get(failed.Id).Retry_Count__c,
            'A handler-failed record below the configured retry cap should increment retry count.');
        Assert.areEqual('handler rejected record', updatesById.get(failed.Id).Error_Message__c,
            'A handler-failed record should preserve the failure message.');
        Assert.areEqual(EventRelay.DONE, updatesById.get(defaultCompleted.Id).Status__c,
            'A handler record with no explicit result should be marked done.');
    }

    @istest static void workFail_retriesProcessWorkUntilConfiguredCap() {
        EventRelay.reset();
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        Event__c retryable = processWorkItem('1001');
        Event__c terminal = processWorkItem('1002');
        terminal.Retry_Count__c = 1;
        Event_Config__mdt config = eventConfig(
            retryable.Route__c,
            EventRelay.INGEST,
            EventRelay.GENERIC_PAYLOAD,
            'type',
            'order',
            MockHandler.class.getName(),
            null
        );
        config.Max_Retries__c = 1;
        EventRelay.metadata = new MockMetadataService(new List<Event_Config__mdt> { config });
        EventRelay.queries = new MockQueryService(new List<Event__c> { retryable, terminal });

        EventRelay.work.fail(new Set<Id> { retryable.Id, terminal.Id }, 'handler failed', 'handler stack');

        Map<Id, Event__c> updatesById = new Map<Id, Event__c>();
        for (SObject updateRecord : dmlMock.updates[0]) {
            updatesById.put(updateRecord.Id, (Event__c) updateRecord);
        }
        Assert.areEqual(EventRelay.PENDING, updatesById.get(retryable.Id).Status__c,
            'Failed process work below the configured retry cap should move back to pending.');
        Assert.areEqual(1, updatesById.get(retryable.Id).Retry_Count__c,
            'Failed process work below the configured retry cap should increment retry count.');
        Assert.areEqual('handler failed', updatesById.get(retryable.Id).Error_Message__c,
            'Retried process work should preserve the latest handler error message.');
        Assert.areEqual('handler stack', updatesById.get(retryable.Id).Error_Stack_Trace__c,
            'Retried process work should preserve the latest handler stack trace.');
        Assert.areEqual(EventRelay.ERROR, updatesById.get(terminal.Id).Status__c,
            'Failed process work at the configured retry cap should become terminal error work.');
        Assert.areEqual(null, updatesById.get(terminal.Id).Retry_Count__c,
            'Terminal process work should not increment retry count beyond the configured cap.');
        Assert.areEqual('handler failed', updatesById.get(terminal.Id).Error_Message__c,
            'Terminal process work should preserve the latest handler error message.');
        Assert.areEqual('handler stack', updatesById.get(terminal.Id).Error_Stack_Trace__c,
            'Terminal process work should preserve the latest handler stack trace.');
    }

    @istest static void retry_requeuesRetryableWorkAndReopensThread() {
        EventRelay.reset();
        MockWakeService wakeSignal = new MockWakeService();
        EventRelay.wakeSignal = wakeSignal;

        Thread__c threadRecord = new Thread__c(
            Status__c = Thread.DONE,
            Pool__c = EventRelay.PUBLISH_POOL,
            Thread_Key__c = 'Bedrock_Test_Event__e',
            Completed__c = System.now(),
            Run_Key__c = 'old-run-key',
            Heartbeat__c = System.now()
        );
        insert threadRecord;

        Event__c errored = workItem('errored');
        errored.Id = null;
        errored.Status__c = EventRelay.ERROR;
        errored.Thread__c = threadRecord.Id;
        errored.Thread_Key__c = 'Bedrock_Test_Event__e';
        errored.Retry_Count__c = 3;
        errored.Error_Message__c = 'publish failed';
        errored.Error_Stack_Trace__c = 'stack';

        Event__c paused = workItem('paused');
        paused.Id = null;
        paused.Status__c = EventRelay.PAUSED;
        paused.Thread__c = threadRecord.Id;
        paused.Thread_Key__c = 'Bedrock_Test_Event__e';
        paused.Retry_Count__c = 1;
        paused.Error_Message__c = 'limit unsafe';

        Event__c done = workItem('done');
        done.Id = null;
        done.Status__c = EventRelay.DONE;
        done.Thread__c = threadRecord.Id;
        done.Thread_Key__c = 'Bedrock_Test_Event__e';

        insert new List<Event__c> { errored, paused, done };

        Test.startTest();
        List<Id> retriedIds = EventRelay.retry(new Set<Id> { errored.Id, paused.Id, done.Id });
        Test.stopTest();

        Assert.areEqual(new Set<Id> { errored.Id, paused.Id }, new Set<Id>(retriedIds),
            'Manual retry should return only work items moved back to pending.');

        Set<Id> workItemIds = new Set<Id> { errored.Id, paused.Id, done.Id };
        Map<Id, Event__c> workById = new Map<Id, Event__c>([
            SELECT Status__c, Retry_Count__c, Error_Message__c, Error_Stack_Trace__c
            FROM Event__c
            WHERE Id IN :workItemIds
        ]);
        Assert.areEqual(EventRelay.PENDING, workById.get(errored.Id).Status__c,
            'Manual retry should requeue errored work.');
        Assert.areEqual(3, workById.get(errored.Id).Retry_Count__c,
            'Manual retry should preserve the existing retry count.');
        Assert.areEqual(null, workById.get(errored.Id).Error_Message__c,
            'Manual retry should clear the latest error message.');
        Assert.areEqual(null, workById.get(errored.Id).Error_Stack_Trace__c,
            'Manual retry should clear the latest error stack trace.');
        Assert.areEqual(EventRelay.PENDING, workById.get(paused.Id).Status__c,
            'Manual retry should requeue paused work.');
        Assert.areEqual(1, workById.get(paused.Id).Retry_Count__c,
            'Manual retry should preserve retry count on paused work.');
        Assert.areEqual(null, workById.get(paused.Id).Error_Message__c,
            'Manual retry should clear the pause reason before rerunning.');
        Assert.areEqual(EventRelay.DONE, workById.get(done.Id).Status__c,
            'Manual retry should ignore non-retryable work.');

        Thread__c reopenedThread = [
            SELECT Status__c, Completed__c, Run_Key__c
            FROM Thread__c
            WHERE Id = :threadRecord.Id
        ];
        Assert.areEqual(Thread.PENDING, reopenedThread.Status__c,
            'Manual retry should reopen a drained EventRelay lane.');
        Assert.areEqual(null, reopenedThread.Completed__c,
            'Manual retry should clear the lane completed timestamp.');
        Assert.areEqual(null, reopenedThread.Run_Key__c,
            'Manual retry should clear the stale lane run key.');
        Assert.areEqual(1, wakeSignal.signalCalls,
            'Manual retry should signal EventRelay wake processing.');
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

    @istest static void genericPublisher_canExplicitlyCompleteAndFailRecords() {
        PartialResultGenericPublisher publisher = new PartialResultGenericPublisher();

        List<EventRelay.PublishResult> results = publisher.publish(new List<EventRelay.PublishPayload> {
            new EventRelay.PublishPayload(null, 'Webhook:OrderService', EventRelay.GENERIC_PAYLOAD,
                new Generic(new Map<String, Object> { 'orderNumber' => '1001' })),
            new EventRelay.PublishPayload(null, 'Webhook:OrderService', EventRelay.GENERIC_PAYLOAD,
                new Generic(new Map<String, Object> { 'orderNumber' => '1002' })),
            new EventRelay.PublishPayload(null, 'Webhook:OrderService', EventRelay.GENERIC_PAYLOAD,
                new Generic(new Map<String, Object> { 'orderNumber' => '1003' }))
        });

        Assert.areEqual(3, results.size(),
            'GenericPublisher should return one result per payload after explicit item-level result handling.');
        Assert.isTrue(results[0].success,
            'GenericPublisher.complete should mark the selected record successful.');
        Assert.isFalse(results[1].success,
            'GenericPublisher.fail should fail only the selected record.');
        Assert.areEqual('rejected', results[1].message,
            'GenericPublisher.fail should preserve the item-level failure message.');
        Assert.isTrue(results[2].success,
            'GenericPublisher should mark records successful when they are not explicitly failed.');
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

    static Event__c processWorkItem(String orderNumber) {
        EventRelay.PayloadService payloads = new EventRelay.PayloadService();
        Event__c workItem = (Event__c) new TestData(Event__c.sObjectType)
            .mockIds()
            .build()[0];
        workItem.Apex__c = MockHandler.class.getName();
        workItem.Job_Type__c = EventRelay.PROCESS;
        workItem.Route__c = 'Webhook:OrderService';
        workItem.Payload_Type__c = EventRelay.GENERIC_PAYLOAD;
        payloads.write(workItem, new Generic(new Map<String, Object> { 'orderNumber' => orderNumber }).json());
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

    static Event_Config__mdt eventConfig(
        String developerName,
        String direction,
        String sourceType,
        String routingKey,
        String routingValue,
        String apexClass,
        Integer batchSize
    ) {
        return new Event_Config__mdt(
            DeveloperName = developerName,
            MasterLabel = developerName,
            Active__c = true,
            Direction__c = direction,
            Source_Type__c = sourceType,
            Routing_Key__c = routingKey,
            Routing_Value__c = routingValue,
            Apex__c = apexClass,
            Batch_Size__c = batchSize
        );
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

    private class MockHandlerService extends EventRelay.HandlerService {
        EventRelay.Handler handler;

        MockHandlerService(EventRelay.Handler handler) {
            this.handler = handler;
        }

        public override EventRelay.Handler forWorkItems(List<Event__c> workItems) {
            return handler;
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

        public override List<EventRelay.Route> forSObject(String payloadType, String direction) {
            return routes;
        }

        public override List<EventRelay.Route> forGeneric(Generic payload) {
            return routes;
        }

        public override List<EventRelay.Route> forGeneric(Generic payload, String direction) {
            return routes;
        }
    }

    private class MockMetadataService extends EventRelay.MetadataService {
        List<Event_Config__mdt> configs;

        MockMetadataService(List<Event_Config__mdt> configs) {
            this.configs = configs;
        }

        protected override List<Event_Config__mdt> loadConfigs() {
            return configs;
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

    private class MockHandler extends EventRelay.Handler {
        List<Generic> records = new List<Generic>();

        public override void execute(List<Generic> records) {
            this.records = records;
        }
    }

    private class PartialResultHandler extends EventRelay.Handler {
        List<Generic> records = new List<Generic>();

        public override void execute(List<Generic> records) {
            this.records = records;
            complete(records[0]);
            fail(records[1], 'handler rejected record');
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

    private class PartialResultGenericPublisher extends EventRelay.Publisher {
        public override void execute(List<Generic> records) {
            complete(records[0]);
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
