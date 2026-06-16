@istest(testFor='ApexClass:ThreadRunner')
public with sharing class ThreadRunnerTest {
    @istest static void testExecute_usesDispatcherForThreadPool() {
        Thread__c threadRecord = new Thread__c(
            Status__c = Thread.RUNNING,
            Pool__c = 'TestPool',
            Thread_Key__c = 'TestLane',
            Lane_Key__c = 'TestPool:TestLane'
        );
        insert threadRecord;

        SpyDispatcher dispatcher = new SpyDispatcher();
        ThreadRunner.Service runner = new ThreadRunner.Service();
        runner.register('TestPool', dispatcher);
        ThreadRunner.setMock(runner);

        new ThreadRunner(threadRecord.Id, 2).execute(null);

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
            Lane_Key__c = 'TestPool:PendingLane'
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
}
