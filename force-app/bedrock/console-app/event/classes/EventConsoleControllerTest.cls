@istest(testFor='ApexClass:EventConsoleController')
public with sharing class EventConsoleControllerTest {
    @istest static void testGetState_countsPublishWorkAndReturnsRows() {
        Thread__c publishThread = threadRecord(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        Thread__c processThread = threadRecord('EventRelayProcess', 'Account');
        DML.insertRecords(new List<SObject>{ publishThread, processThread });

        DML.insertRecords(new List<SObject>{
            workItem(EventRelay.PENDING, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', null),
            workItem(EventRelay.RUNNING, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', null),
            workItem(EventRelay.PAUSED, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', 'Publish limit is not safe.'),
            workItem(EventRelay.ERROR, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', 'Publish failed.'),
            workItem(EventRelay.DONE, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', null),
            workItem(EventRelay.ERROR, 'Process', processThread.Id, 'Account', 'Processing failed.')
        });

        Test.startTest();
        EventConsoleController.ConsoleState state = EventConsoleController.getState();
        Test.stopTest();

        Assert.areEqual(2, state.metrics.backlog, 'Expected pending and paused publish work to be counted as backlog.');
        Assert.areEqual(1, state.metrics.running, 'Expected running publish work to be counted.');
        Assert.areEqual(1, state.metrics.errors, 'Expected only failed publish work to be counted as errors.');
        Assert.areEqual(1, state.metrics.publishedToday, 'Expected completed publish work modified today to be counted.');
        Assert.areEqual(2, state.backlogRows.size(), 'Expected backlog rows to include pending and paused publish work.');
        Assert.areEqual(1, state.runningRows.size(), 'Expected running rows to include running publish work.');
        Assert.areEqual(1, state.errorRows.size(), 'Expected error rows to include failed publish work.');
        Assert.areEqual(1, state.archiveRows.size(), 'Expected archive rows to include completed publish work.');
        Assert.areEqual(1, state.configRows.size(), 'Expected config rows to summarize publish routes from Event records.');
        Assert.areEqual(5, state.configRows[0].workItems, 'Expected config rows to count only publish work items.');
        Assert.areEqual(50, state.settings.publishBatchSize, 'Expected settings to expose the effective publish batch size.');
        Assert.areEqual(90, state.settings.limitThresholdPct, 'Expected settings to expose the event limit safety threshold.');
        Assert.areEqual(EventRelay.PUBLISH_POOL, state.settings.publishPool, 'Expected settings to expose the publish thread pool.');
        Assert.areEqual(publishThread.Id, state.backlogRows[0].threadId, 'Expected rows to expose the owning thread.');
        Assert.isNotNull(state.backlogRows[0].threadName, 'Expected rows to expose a thread display name.');
    }

    static Thread__c threadRecord(String pool, String threadKey) {
        return new Thread__c(
            Status__c = Thread.PENDING,
            Pool__c = pool,
            Thread_Key__c = threadKey,
            Heartbeat__c = System.now()
        );
    }

    static Event__c workItem(String status, String jobType, Id threadId, String payloadType, String errorMessage) {
        return new Event__c(
            Apex__c = 'EventRelay.PlatformEventPublisher',
            Job_Type__c = jobType,
            Status__c = status,
            Route__c = payloadType,
            Payload_Type__c = payloadType,
            Thread__c = threadId,
            Thread_Key__c = payloadType,
            Order__c = 0,
            Retry_Count__c = 0,
            Error_Message__c = errorMessage
        );
    }
}
