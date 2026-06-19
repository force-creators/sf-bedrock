@istest(testFor='ApexClass:ThreadRunner')
public with sharing class ThreadRunnerTest {
    @istest static void testExecute_usesDispatcherForThreadPool() {
        Thread__c threadRecord = new Thread__c(
            Status__c = Thread.RUNNING,
            Pool__c = 'TestPool',
            Thread_Key__c = 'TestLane',
            Unique_Key__c = 'TestPoolTestLane000000000000000000000000000000000000000000000000',
            Run_Key__c = 'active-run-key'
        );
        insert threadRecord;

        SpyDispatcher dispatcher = new SpyDispatcher();
        ThreadRunner.Service runner = new ThreadRunner.Service();
        runner.register('TestPool', dispatcher);
        ThreadRunner.setMock(runner);

        new ThreadRunner(threadRecord.Id, 2, 'active-run-key').execute(null);

        Assert.areEqual(threadRecord.Id, Thread.currentId(), 'Expected ThreadRunner to adopt the thread before dispatching work.');
        Assert.areEqual(1, dispatcher.dispatchCalls, 'Expected ThreadRunner to dispatch work through the registered pool dispatcher.');
        Assert.areEqual(threadRecord.Id, dispatcher.lastThreadId, 'Expected ThreadRunner to pass the thread id to the registered dispatcher.');
        Assert.areEqual(2, dispatcher.lastFailures, 'Expected ThreadRunner to pass the failure streak to the registered dispatcher.');
    }

    @istest static void testHasPendingWork_usesDispatcherForThreadPool() {
        Thread__c threadRecord = new Thread__c(
            Status__c = Thread.RUNNING,
            Pool__c = 'TestPool',
            Thread_Key__c = 'PendingLane',
            Unique_Key__c = 'TestPoolPendingLane00000000000000000000000000000000000000000000'
        );
        insert threadRecord;

        SpyDispatcher dispatcher = new SpyDispatcher();
        dispatcher.hasPendingWork = true;
        ThreadRunner.Service runner = new ThreadRunner.Service();
        runner.register('TestPool', dispatcher);
        ThreadRunner.setMock(runner);

        Boolean hasPendingWork = ThreadRunner.service.hasPendingWork(threadRecord.Id);

        Assert.isTrue(hasPendingWork, 'Expected ThreadRunner pending-work checks to come from the registered pool dispatcher.');
        Assert.areEqual(threadRecord.Id, dispatcher.lastThreadId, 'Expected ThreadRunner to pass the thread id to the pending-work check.');
    }

    @istest static void testDispatch_eventPoolPrioritizesEventWorkBeforeAsyncWork() {
        Thread__c threadRecord = thread(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        insert threadRecord;
        SpyDispatcher eventDispatcher = new SpyDispatcher();
        eventDispatcher.hasPendingWork = true;
        SpyDispatcher asyncDispatcher = new SpyDispatcher();
        asyncDispatcher.hasPendingWork = true;
        ThreadRunner.Service runner = new ThreadRunner.Service();
        runner.register(EventRelay.PUBLISH_POOL, eventDispatcher);
        runner.register(Thread.ASYNC_POOL, asyncDispatcher);
        ThreadRunner.setMock(runner);

        ThreadRunner.service.dispatch(threadRecord.Id, 0, 'active-run-key');

        Assert.areEqual(1, eventDispatcher.dispatchCalls,
            'Expected EventRelay work to run before same-thread Async work.');
        Assert.areEqual(0, asyncDispatcher.dispatchCalls,
            'Expected same-thread Async work to wait while EventRelay work remains.');
    }

    @istest static void testDispatch_eventPoolFallsBackToSameThreadAsyncWork() {
        Thread__c threadRecord = thread(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        insert threadRecord;
        SpyDispatcher eventDispatcher = new SpyDispatcher();
        eventDispatcher.hasPendingWork = false;
        SpyDispatcher asyncDispatcher = new SpyDispatcher();
        asyncDispatcher.hasPendingWork = true;
        ThreadRunner.Service runner = new ThreadRunner.Service();
        runner.register(EventRelay.PUBLISH_POOL, eventDispatcher);
        runner.register(Thread.ASYNC_POOL, asyncDispatcher);
        ThreadRunner.setMock(runner);

        ThreadRunner.service.dispatch(threadRecord.Id, 0, 'active-run-key');

        Assert.areEqual(0, eventDispatcher.dispatchCalls,
            'Expected EventRelay dispatch to stop when the event lane has no pending work.');
        Assert.areEqual(1, asyncDispatcher.dispatchCalls,
            'Expected same-thread Async work to run after EventRelay work drains.');
        Assert.areEqual(threadRecord.Id, asyncDispatcher.lastThreadId,
            'Expected the Async dispatcher to receive the original EventRelay thread id.');
    }

    @istest static void testDispatch_processPoolFallsBackToSameThreadAsyncWork() {
        Thread__c threadRecord = thread(EventRelay.PROCESS_POOL, 'Bedrock_Test_Event__e');
        insert threadRecord;
        SpyDispatcher processDispatcher = new SpyDispatcher();
        processDispatcher.hasPendingWork = false;
        SpyDispatcher asyncDispatcher = new SpyDispatcher();
        asyncDispatcher.hasPendingWork = true;
        ThreadRunner.Service runner = new ThreadRunner.Service();
        runner.register(EventRelay.PROCESS_POOL, processDispatcher);
        runner.register(Thread.ASYNC_POOL, asyncDispatcher);
        ThreadRunner.setMock(runner);

        ThreadRunner.service.dispatch(threadRecord.Id, 0, 'active-run-key');

        Assert.areEqual(0, processDispatcher.dispatchCalls,
            'Expected EventRelay process dispatch to stop when the process lane has no pending work.');
        Assert.areEqual(1, asyncDispatcher.dispatchCalls,
            'Expected same-thread Async work to run after EventRelay process work drains.');
        Assert.areEqual(threadRecord.Id, asyncDispatcher.lastThreadId,
            'Expected the Async dispatcher to receive the original EventRelay process thread id.');
    }

    public with sharing class SpyDispatcher extends ThreadRunner.Dispatcher {
        public Boolean hasPendingWork = false;
        public Integer dispatchCalls = 0;
        public Integer lastFailures;
        public Id lastThreadId;

        public override void dispatch(Id threadId, Integer failures) {
            this.dispatchCalls++;
            this.lastThreadId = threadId;
            this.lastFailures = failures;
        }

        public override Boolean hasPendingWork(Id threadId) {
            this.lastThreadId = threadId;
            return this.hasPendingWork;
        }
    }

    static Thread__c thread(String pool, String threadKey) {
        return new Thread__c(
            Status__c = Thread.RUNNING,
            Pool__c = pool,
            Thread_Key__c = threadKey,
            Unique_Key__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(pool + ':' + threadKey))),
            Run_Key__c = 'active-run-key'
        );
    }
}
