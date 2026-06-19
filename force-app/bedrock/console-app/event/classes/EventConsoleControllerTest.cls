@istest(testFor='ApexClass:EventConsoleController')
public with sharing class EventConsoleControllerTest {
    @istest static void testGetState_countsPublishWorkAndReturnsRows() {
        Thread__c publishThread = threadRecord(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        Thread__c processThread = threadRecord('EventRelayProcess', 'Account');
        DML.insertRecords(new List<SObject>{ publishThread, processThread });

        DML.insertRecords(new List<SObject>{
            workItem(EventRelay.PENDING, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', null),
            workItem(EventRelay.RUNNING, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', null),
            workItem(EventRelay.ERROR, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', 'Publish failed.'),
            workItem(EventRelay.DONE, EventRelay.PUBLISH, publishThread.Id, 'Bedrock_Test_Event__e', null),
            workItem(EventRelay.ERROR, 'Process', processThread.Id, 'Account', 'Processing failed.')
        });

        Test.startTest();
        EventConsoleController.ConsoleState state = EventConsoleController.getState();
        Test.stopTest();

        Assert.areEqual(1, state.metrics.backlog, 'Expected pending publish work to be counted as backlog.');
        Assert.areEqual(1, state.metrics.running, 'Expected running publish work to be counted.');
        Assert.areEqual(1, state.metrics.errors, 'Expected only failed publish work to be counted as errors.');
        Assert.areEqual(1, state.metrics.publishedToday, 'Expected completed publish work modified today to be counted.');
        Assert.areEqual(1, state.backlogRows.size(), 'Expected backlog rows to include pending publish work.');
        Assert.areEqual(1, state.runningRows.size(), 'Expected running rows to include running publish work.');
        Assert.areEqual(1, state.errorRows.size(), 'Expected error rows to include failed publish work.');
        Assert.areEqual(1, state.archiveRows.size(), 'Expected archive rows to include completed publish work.');
        Assert.areEqual(1, state.configRows.size(), 'Expected config rows to summarize publish routes from Event records.');
        Assert.areEqual(4, state.configRows[0].workItems, 'Expected config rows to count only publish work items.');
        Assert.areEqual(50, state.settings.publishBatchSize, 'Expected settings to expose the effective publish batch size.');
        Assert.areEqual(90, state.settings.limitThresholdPct, 'Expected settings to expose the event limit safety threshold.');
        Assert.areEqual(EventRelay.PUBLISH_POOL, state.settings.publishPool, 'Expected settings to expose the publish thread pool.');
        Assert.areEqual(publishThread.Id, state.backlogRows[0].threadId, 'Expected rows to expose the owning thread.');
        Assert.isNotNull(state.backlogRows[0].threadName, 'Expected rows to expose a thread display name.');
    }

    @istest static void testRetryWorkItems_requeuesRetryableWork() {
        EventRelay.reset();
        EventRelay.wakeSignal = new WakeServiceMock();

        Thread__c publishThread = threadRecord(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        publishThread.Status__c = Thread.DONE;
        publishThread.Completed__c = System.now();
        publishThread.Run_Key__c = 'old-run-key';
        insert publishThread;

        Event__c errored = workItem(
            EventRelay.ERROR,
            EventRelay.PUBLISH,
            publishThread.Id,
            'Bedrock_Test_Event__e',
            'Publish failed.'
        );
        Event__c done = workItem(
            EventRelay.DONE,
            EventRelay.PUBLISH,
            publishThread.Id,
            'Bedrock_Test_Event__e',
            null
        );
        insert new List<Event__c> { errored, done };

        Test.startTest();
        Integer retryCount = EventConsoleController.retryWorkItems(new List<Id> { errored.Id, done.Id });
        Test.stopTest();

        Assert.areEqual(1, retryCount, 'Expected the console retry action to count only requeued work.');

        Set<Id> workItemIds = new Set<Id> { errored.Id, done.Id };
        Map<Id, Event__c> workById = new Map<Id, Event__c>([
            SELECT Status__c, Error_Message__c
            FROM Event__c
            WHERE Id IN :workItemIds
        ]);
        Assert.areEqual(EventRelay.PENDING, workById.get(errored.Id).Status__c,
            'Expected console retry to requeue failed work.');
        Assert.areEqual(null, workById.get(errored.Id).Error_Message__c,
            'Expected console retry to clear the failed work error message.');
        Assert.areEqual(EventRelay.DONE, workById.get(done.Id).Status__c,
            'Expected console retry to ignore completed work.');
    }

    @istest static void testDeleteWorkItems_deletesOnlyFailedPublishWork() {
        Thread__c publishThread = threadRecord(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        Thread__c processThread = threadRecord('EventRelayProcess', 'Account');
        DML.insertRecords(new List<SObject>{ publishThread, processThread });

        Event__c errored = workItem(
            EventRelay.ERROR,
            EventRelay.PUBLISH,
            publishThread.Id,
            'Bedrock_Test_Event__e',
            'Publish failed.'
        );
        Event__c done = workItem(
            EventRelay.DONE,
            EventRelay.PUBLISH,
            publishThread.Id,
            'Bedrock_Test_Event__e',
            null
        );
        Event__c processError = workItem(
            EventRelay.ERROR,
            'Process',
            processThread.Id,
            'Account',
            'Processing failed.'
        );
        DML.insertRecords(new List<SObject> { errored, done, processError });

        Test.startTest();
        Integer deleteCount = EventConsoleController.deleteWorkItems(new List<Id> {
            errored.Id,
            done.Id,
            processError.Id
        });
        Test.stopTest();

        Assert.areEqual(1, deleteCount, 'Expected the console delete action to count only failed publish work.');

        Set<Id> workItemIds = new Set<Id> { errored.Id, done.Id, processError.Id };
        Map<Id, Event__c> workById = new Map<Id, Event__c>([
            SELECT Status__c, Job_Type__c
            FROM Event__c
            WHERE Id IN :workItemIds
        ]);
        Assert.isFalse(workById.containsKey(errored.Id), 'Expected console delete to delete failed publish work.');
        Assert.isTrue(workById.containsKey(done.Id), 'Expected console delete to ignore completed publish work.');
        Assert.isTrue(workById.containsKey(processError.Id), 'Expected console delete to ignore handler work.');
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

    class WakeServiceMock extends EventRelay.WakeService {
        public override void signal() {
        }
    }
}
