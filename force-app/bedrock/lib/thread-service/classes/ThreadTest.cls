@istest(testFor='ApexClass:Thread')
public with sharing class ThreadTest {
    @istest static void testCurrentOrCreate_returnsCreatedThreadId() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);

        Id threadId = Thread.currentOrCreate();
        Thread__c threadRecord = [
            SELECT Pool__c, Thread_Key__c, Unique_Key__c
            FROM Thread__c
            WHERE Id = :threadId
        ];

        Assert.areEqual(threadId, Thread.currentId(), 'Expected Thread.currentOrCreate to cache the created thread id.');
        Assert.isNotNull(threadId, 'Expected Thread.currentOrCreate to return a usable thread id.');
        Assert.areEqual(Thread.ASYNC_POOL, threadRecord.Pool__c, 'Expected Thread.currentOrCreate to tag new threads with the Async pool by default.');
        Assert.isTrue(threadRecord.Thread_Key__c.startsWith('request:'), 'Expected Thread.currentOrCreate to store a request-scoped thread key by default.');
        Assert.areEqual(64, threadRecord.Unique_Key__c.length(),
            'Expected Thread.currentOrCreate to store a generated hash key for uniqueness.');
    }

    @istest static void testCurrentOrCreate_cachesByPoolAndThreadKey() {
        Thread.setMock(new ThreadMock());

        Id asyncThreadId = Thread.currentOrCreate();
        Id eventThreadId = Thread.currentOrCreate('EventConsume', 'AccountChanged');
        Id sameEventThreadId = Thread.currentOrCreate('EventConsume', 'AccountChanged');
        List<Thread__c> threads = [
            SELECT Pool__c, Thread_Key__c, Unique_Key__c
            FROM Thread__c
            WHERE Id IN :new Set<Id> { asyncThreadId, eventThreadId }
        ];

        Assert.areNotEqual(asyncThreadId, eventThreadId,
            'Expected distinct pool/thread keys to resolve to distinct Thread__c rows in the same transaction.');
        Assert.areEqual(eventThreadId, sameEventThreadId,
            'Expected repeated calls for the same pool/thread key to reuse the cached Thread__c row.');
        Assert.areEqual(eventThreadId, Thread.currentId(),
            'Expected Thread.currentId to track the most recently resolved thread.');
        Assert.areEqual(2, threads.size(), 'Expected exactly one thread per distinct pool/thread key.');
    }

    @istest static void testQueryService_getNextPendingThreadFiltersByPool() {
        Thread__c asyncThread = thread(Thread.ASYNC_POOL, 'request:oldest');
        Thread__c eventThread = thread('EventConsume', 'AccountChanged');
        insert new List<Thread__c> { asyncThread, eventThread };

        Thread__c nextEventThread = new Thread.QueryService().getNextPendingThread('EventConsume');

        Assert.areEqual(eventThread.Id, nextEventThread.Id,
            'Expected pending-thread claims to select work from the requested pool.');
    }

    @istest static void testContinueCurrent_restartsCurrentThreadAtFailureThreshold() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        Id threadId = Thread.currentOrCreate();
        Async.queries = new PendingWorkQueryService();

        Thread.continueCurrent(4);

        Assert.areEqual(1, mock.service.startCalls, 'Expected Thread to restart the current thread at the failure threshold.');
        Assert.areEqual(threadId, mock.service.startedThreads[0], 'Expected Thread to restart the same current thread.');
        Assert.areEqual(0, mock.service.lastFailures, 'Expected Thread to reset failures when restarting a thread.');
    }

    @istest static void testContinueCurrent_continuesCurrentWorkBelowFailureThreshold() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        Id threadId = Thread.currentOrCreate();
        Async.queries = new PendingWorkQueryService();
        Async.jobs = new SpyJobService();

        Thread.continueCurrent(2);

        Assert.areEqual(1, mock.service.continueWorkCalls, 'Expected Thread to continue current work below the failure threshold.');
        Assert.areEqual(0, mock.service.startCalls, 'Expected Thread not to restart below the failure threshold.');
        Assert.areEqual(threadId, ((SpyJobService) Async.jobs).lastThreadId, 'Expected Thread to continue work on the current thread.');
        Assert.areEqual(2, ((SpyJobService) Async.jobs).lastFailures, 'Expected Thread to carry the failure count into current work.');
    }

    @istest static void testContinueCurrent_claimsNextThreadWhenCurrentIsDrained() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        Thread.currentOrCreate();
        Thread__c nextThread = new Thread__c(Status__c = Thread.PENDING);
        insert nextThread;
        mock.queries.pendingThreads.add(nextThread);
        Async.queries = new EmptyWorkQueryService();

        Thread.continueCurrent();

        Assert.areEqual(nextThread.Id, Thread.currentId(), 'Expected Thread to adopt the next pending thread when current work is drained.');
        Assert.areEqual(1, mock.service.startCalls, 'Expected Thread to start the claimed pending thread.');
        Assert.areEqual(nextThread.Id, mock.service.startedThreads[0], 'Expected Thread to start the claimed pending thread id.');
    }

    @istest static void testEnqueue_startsThreadWhenSlotIsAvailable() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue()
            .seedSettings(new Async_Settings__c(Max_Threads__c = 2));
        Async.setMock(mock);
        mock.threads.runningThreads(1);
        Id threadId = Thread.currentOrCreate();
        mock.threads.queries.pendingThreads.add(new Thread__c(Id = threadId, Status__c = Thread.PENDING));

        Thread.enqueue();

        Assert.areEqual(1, mock.threads.service.startCalls, 'Expected Thread.enqueue to start work when the user is below the thread cap.');
        Assert.areEqual(threadId, Thread.currentId(), 'Expected Thread.enqueue to start and cache the claimed pending thread id.');
    }

    @istest static void testEnqueue_claimsOlderPendingThreadBeforeCurrentThread() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue()
            .seedSettings(new Async_Settings__c(Max_Threads__c = 2));
        Async.setMock(mock);
        mock.threads.runningThreads(1);
        Thread__c olderPendingThread = new Thread__c(Status__c = Thread.PENDING);
        insert olderPendingThread;
        Id currentThreadId = Thread.currentOrCreate();
        mock.threads.queries.pendingThreads.add(olderPendingThread);

        Thread.enqueue();

        Assert.areEqual(1, mock.threads.service.startCalls, 'Expected Thread.enqueue to start one pending thread when capacity is available.');
        Assert.areEqual(olderPendingThread.Id, mock.threads.service.startedThreads[0],
            'Expected Thread.enqueue to start the oldest pending thread instead of the current transaction thread.');
        Assert.areEqual(olderPendingThread.Id, Thread.currentId(),
            'Expected Thread.enqueue to adopt the claimed backlog thread as current.');
        Assert.areNotEqual(currentThreadId, mock.threads.service.startedThreads[0],
            'Expected the newly-created current thread to remain pending behind older backlog.');
    }

    @istest static void testClaimNextLeavesPendingThreadWhenSlotFillsBeforeStatusUpdate() {
        AsyncMock mock = new AsyncMock()
            .seedSettings(new Async_Settings__c(Max_Threads__c = 1));
        Async.setMock(mock);
        mock.threads.runningThreadCounts(new List<Integer> { 0, 1 });
        Thread__c pendingThread = new Thread__c(Status__c = Thread.PENDING);
        insert pendingThread;
        mock.threads.queries.pendingThreads.add(pendingThread);

        Id claimedThreadId = Thread.service.claimNext();

        Thread__c storedThread = [
            SELECT Status__c
            FROM Thread__c
            WHERE Id = :pendingThread.Id
        ];
        Assert.areEqual(null, claimedThreadId,
            'Expected Thread.claimNext to stop when thread capacity is no longer available after selecting a pending thread.');
        Assert.areEqual(Thread.PENDING, storedThread.Status__c,
            'Expected Thread.claimNext to leave the selected thread pending when no slot remains.');
    }

    @istest static void testEnqueue_doesNotStartThreadWhenCapIsFull() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue()
            .mockThreadIds()
            .seedSettings(new Async_Settings__c(Max_Threads__c = 1));
        Async.setMock(mock);
        mock.threads.runningThreads(1);

        Thread.enqueue();

        Assert.areEqual(0, mock.threads.service.startCalls, 'Expected Thread.enqueue to leave pending work alone when the user is at the thread cap.');
        Assert.areEqual(null, Thread.currentId(), 'Expected Thread.enqueue not to create a new thread when no slot is available.');
    }

    @istest static void testContinueCurrent_doesNotClaimNextThreadWhenCapIsFull() {
        ThreadMock mock = new ThreadMock()
            .runningThreads(1);
        Thread.setMock(mock);
        Thread.currentOrCreate();
        Thread__c nextThread = new Thread__c(Status__c = Thread.PENDING);
        insert nextThread;
        mock.queries.pendingThreads.add(nextThread);
        Async.queries = new EmptyWorkQueryService();
        Async.settings.setSettings(new Async_Settings__c(Max_Threads__c = 1));

        Thread.continueCurrent();

        Assert.areEqual(0, mock.service.startCalls, 'Expected Thread not to claim another pending thread while the cap is full.');
        Assert.areNotEqual(nextThread.Id, Thread.currentId(), 'Expected Thread to leave the pending thread unclaimed when no slot is available.');
    }

    @istest static void testDeleteDrained_deletesOnlyThreadsWithoutAsyncWork() {
        Thread__c drainedThread = new Thread__c(Status__c = Thread.DONE);
        Thread__c activeThread = new Thread__c(Status__c = Thread.DONE);
        insert new List<Thread__c> { drainedThread, activeThread };

        DML.insertRecords(new List<SObject> {
            workItem(String.valueOf(ThreadTest.class), UserInfo.getUserId(), 'Done', activeThread.Id)
        });

        Thread.deleteDrained(new Set<Id> { drainedThread.Id, activeThread.Id });

        Map<Id, Thread__c> remainingThreads = new Map<Id, Thread__c>([
            SELECT Id
            FROM Thread__c
            WHERE Id IN :new Set<Id> { drainedThread.Id, activeThread.Id }
        ]);
        Assert.isFalse(remainingThreads.containsKey(drainedThread.Id), 'Expected Thread.deleteDrained to delete threads with no remaining async work.');
        Assert.isTrue(remainingThreads.containsKey(activeThread.Id), 'Expected Thread.deleteDrained to keep threads that still have async work.');
    }

    public with sharing class EmptyWorkQueryService extends Async.QueryService {
        public override Boolean hasPendingWork(Id threadId) {
            return false;
        }
    }

    public with sharing class PendingWorkQueryService extends Async.QueryService {
        public override Boolean hasPendingWork(Id threadId) {
            return true;
        }
    }

    public with sharing class SpyJobService extends Async.JobService {
        public Id lastThreadId;
        public Integer lastFailures;

        public override void enqueueNextJob(Id threadId, Integer failures) {
            this.lastThreadId = threadId;
            this.lastFailures = failures;
        }
    }

    static Async__c workItem(String apexClass, Id recordId, String status, Id threadId) {
        Async__c workItem = new Async__c(
            Apex__c = apexClass,
            Record_Id__c = String.valueOf(recordId),
            Status__c = status
        );
        workItem.put('Thread__c', threadId);
        return workItem;
    }

    static Thread__c thread(String pool, String threadKey) {
        return new Thread__c(
            Status__c = Thread.PENDING,
            Pool__c = pool,
            Thread_Key__c = threadKey,
            Unique_Key__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(pool + ':' + threadKey)))
        );
    }
}
