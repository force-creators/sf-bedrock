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
        Id eventThreadId = Thread.currentOrCreate(EventRelay.PROCESS_POOL, 'AccountChanged');
        Id sameEventThreadId = Thread.currentOrCreate(EventRelay.PROCESS_POOL, 'AccountChanged');
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
        Thread__c eventThread = thread(EventRelay.PROCESS_POOL, 'AccountChanged');
        insert new List<Thread__c> { asyncThread, eventThread };

        Thread__c nextEventThread = new Thread.QueryService().getNextPendingThread(EventRelay.PROCESS_POOL);

        Assert.areEqual(eventThread.Id, nextEventThread.Id,
            'Expected pending-thread claims to select work from the requested pool.');
    }

    @istest static void testContinueCurrent_restartsCurrentThreadAtFailureThreshold() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        Id threadId = Thread.currentOrCreate();
        String runKey = Thread.service.startRun(threadId);
        Async.queries = new PendingWorkQueryService();

        Thread.continueCurrent(4, runKey);

        Assert.areEqual(1, mock.service.startCalls, 'Expected Thread to restart the current thread at the failure threshold.');
        Assert.areEqual(threadId, mock.service.startedThreads[0], 'Expected Thread to restart the same current thread.');
        Assert.areEqual(0, mock.service.lastFailures, 'Expected Thread to reset failures when restarting a thread.');
    }

    @istest static void testContinueCurrent_continuesCurrentWorkBelowFailureThreshold() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        Id threadId = Thread.currentOrCreate();
        String runKey = Thread.service.startRun(threadId);
        Async.queries = new PendingWorkQueryService();
        Async.jobs = new SpyJobService();

        Thread.continueCurrent(2, runKey);

        Assert.areEqual(1, mock.service.continueWorkCalls, 'Expected Thread to continue current work below the failure threshold.');
        Assert.areEqual(0, mock.service.startCalls, 'Expected Thread not to restart below the failure threshold.');
        Assert.areEqual(threadId, ((SpyJobService) Async.jobs).lastThreadId, 'Expected Thread to continue work on the current thread.');
        Assert.areEqual(2, ((SpyJobService) Async.jobs).lastFailures, 'Expected Thread to carry the failure count into current work.');
    }

    @istest static void testContinueCurrent_claimsNextThreadWhenCurrentIsDrained() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        Id threadId = Thread.currentOrCreate();
        String runKey = Thread.service.startRun(threadId);
        Thread__c nextThread = new Thread__c(Status__c = Thread.PENDING);
        insert nextThread;
        mock.queries.pendingThreads.add(nextThread);
        Async.queries = new EmptyWorkQueryService();

        Thread.continueCurrent(runKey);

        Assert.areEqual(nextThread.Id, Thread.currentId(), 'Expected Thread to adopt the next pending thread when current work is drained.');
        Assert.areEqual(1, mock.service.startCalls, 'Expected Thread to start the claimed pending thread.');
        Assert.areEqual(nextThread.Id, mock.service.startedThreads[0], 'Expected Thread to start the claimed pending thread id.');
    }

    @istest static void testContinueCurrent_eventDrainClaimsAsyncWorkWhenNoEventWorkRemains() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        ThreadRunner.reset();
        EventRelay.queries = new EmptyEventWorkQueryService();
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
        Thread__c eventThread = thread(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        eventThread.Status__c = Thread.RUNNING;
        Thread__c asyncThread = thread(Thread.ASYNC_POOL, 'event-created-async');
        insert new List<Thread__c> { eventThread, asyncThread };
        Thread.setCurrent(eventThread.Id);
        String runKey = Thread.service.startRun(eventThread.Id);
        mock.queries.pendingThreadsByPool.put(Thread.ASYNC_POOL, new List<Thread__c> { asyncThread });

        Thread.continueCurrent(runKey);

        Assert.areEqual(asyncThread.Id, Thread.currentId(),
            'Expected a drained EventRelay publish thread to hand off to pending Automated Process async work.');
        Assert.areEqual(1, mock.service.startCalls,
            'Expected the EventRelay drain handoff to start the async thread.');
        Assert.areEqual(asyncThread.Id, mock.service.startedThreads[0],
            'Expected the EventRelay drain handoff to start the pending Async pool thread.');
    }

    @istest static void testContinueCurrent_eventThreadContinuesSameThreadAsyncWorkAfterEventsDrain() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        ThreadRunner.reset();
        EventRelay.queries = new EmptyEventWorkQueryService();
        Async.queries = new PendingWorkQueryService();
        Async.jobs = new SpyJobService();
        Thread__c eventThread = thread(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        eventThread.Status__c = Thread.RUNNING;
        insert eventThread;
        Thread.setCurrent(eventThread.Id);
        String runKey = Thread.service.startRun(eventThread.Id);

        Thread.continueCurrent(runKey);

        Assert.areEqual(1, mock.service.continueWorkCalls,
            'Expected a drained EventRelay thread with same-thread Async work to continue before completing.');
        Assert.areEqual(0, mock.service.startCalls,
            'Expected same-thread Async work to run on the current thread instead of claiming a new one.');
        Assert.areEqual(eventThread.Id, ((SpyJobService) Async.jobs).lastThreadId,
            'Expected ThreadRunner to dispatch Async work on the original EventRelay thread.');
    }

    @istest static void testEnqueue_startsThreadWhenSlotIsAvailable() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue();
        Async.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
        mock.threads.runningThreads(1);
        Id threadId = Thread.currentOrCreate();
        mock.threads.queries.pendingThreads.add(new Thread__c(Id = threadId, Status__c = Thread.PENDING));

        Thread.enqueue();

        Assert.areEqual(1, mock.threads.service.startCalls, 'Expected Thread.enqueue to start work when the user is below the thread cap.');
        Assert.areEqual(threadId, Thread.currentId(), 'Expected Thread.enqueue to start and cache the claimed pending thread id.');
    }

    @istest static void testEnqueue_claimsOlderPendingThreadBeforeCurrentThread() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue();
        Async.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
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

    @istest static void testEnqueue_fillsMultipleAvailableSlots() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue();
        Async.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 3));
        mock.threads.runningThreads(0);
        Thread__c oldestPendingThread = new Thread__c(Status__c = Thread.PENDING);
        Thread__c nextPendingThread = new Thread__c(Status__c = Thread.PENDING);
        insert new List<Thread__c> { oldestPendingThread, nextPendingThread };
        Id currentThreadId = Thread.currentOrCreate();
        mock.threads.queries.pendingThreads.add(oldestPendingThread);
        mock.threads.queries.pendingThreads.add(nextPendingThread);
        mock.threads.queries.pendingThreads.add(new Thread__c(Id = currentThreadId, Status__c = Thread.PENDING));

        Thread.enqueue();

        Assert.areEqual(3, mock.threads.service.startCalls,
            'Expected Thread.enqueue to fill each available thread slot from a synchronous transaction.');
        Assert.areEqual(
            new List<Id> { oldestPendingThread.Id, nextPendingThread.Id, currentThreadId },
            mock.threads.service.startedThreads,
            'Expected Thread.enqueue to claim pending backlog before the current transaction thread.');
    }

    @istest static void testEnqueue_stopsAtMaxThreadCapacity() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue();
        Async.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
        mock.threads.runningThreads(1);
        Thread__c firstPendingThread = new Thread__c(Status__c = Thread.PENDING);
        Thread__c secondPendingThread = new Thread__c(Status__c = Thread.PENDING);
        insert new List<Thread__c> { firstPendingThread, secondPendingThread };
        Id currentThreadId = Thread.currentOrCreate();
        mock.threads.queries.pendingThreads.add(firstPendingThread);
        mock.threads.queries.pendingThreads.add(secondPendingThread);
        mock.threads.queries.pendingThreads.add(new Thread__c(Id = currentThreadId, Status__c = Thread.PENDING));

        Thread.enqueue();

        Assert.areEqual(1, mock.threads.service.startCalls,
            'Expected Thread.enqueue to stop after filling the one remaining configured thread slot.');
        Assert.areEqual(firstPendingThread.Id, mock.threads.service.startedThreads[0],
            'Expected Thread.enqueue to claim only the oldest pending thread when one configured slot remains.');
    }

    @istest static void testEnqueue_stopsAtRemainingQueueableCapacity() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue();
        Async.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 3));
        mock.threads.runningThreads(0);
        Thread__c firstPendingThread = new Thread__c(Status__c = Thread.PENDING);
        Thread__c secondPendingThread = new Thread__c(Status__c = Thread.PENDING);
        insert new List<Thread__c> { firstPendingThread, secondPendingThread };
        Id currentThreadId = Thread.currentOrCreate();
        mock.threads.queries.pendingThreads.add(firstPendingThread);
        mock.threads.queries.pendingThreads.add(secondPendingThread);
        mock.threads.queries.pendingThreads.add(new Thread__c(Id = currentThreadId, Status__c = Thread.PENDING));
        for (Integer i = 0; i < 49; i++) {
            System.enqueueJob(new NoOpQueueable());
        }

        Thread.enqueue();

        Assert.areEqual(1, mock.threads.service.startCalls,
            'Expected Thread.enqueue to respect remaining Queueable capacity in the current transaction.');
        Assert.areEqual(firstPendingThread.Id, mock.threads.service.startedThreads[0],
            'Expected Thread.enqueue to spend the last Queueable slot on the oldest pending thread.');
    }

    @istest static void testEnqueue_fillsAvailableSlotsFromTriggerContext() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue();
        Async.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 3));
        mock.threads.runningThreads(0);
        Thread__c olderPendingThread = new Thread__c(Status__c = Thread.PENDING);
        Thread__c newerPendingThread = new Thread__c(Status__c = Thread.PENDING);
        insert new List<Thread__c> { olderPendingThread, newerPendingThread };
        Id currentThreadId = Thread.currentOrCreate();
        mock.threads.queries.pendingThreads.add(olderPendingThread);
        mock.threads.queries.pendingThreads.add(newerPendingThread);
        mock.threads.queries.pendingThreads.add(new Thread__c(Id = currentThreadId, Status__c = Thread.PENDING));

        insert workItem(String.valueOf(NoOpAsync.class), UserInfo.getUserId(), 'Pending', currentThreadId);

        Assert.areEqual(3, mock.threads.service.startCalls,
            'Expected Async__c trigger execution to fill available thread slots because it is still a synchronous enqueue attempt.');
        Assert.areEqual(
            new List<Id> { olderPendingThread.Id, newerPendingThread.Id, currentThreadId },
            mock.threads.service.startedThreads,
            'Expected trigger execution to claim pending backlog before the current transaction thread.');
    }

    @istest static void testEnqueue_doesNotStartThreadFromFinalizerContext() {
        AsyncMock mock = new AsyncMock()
            .canEnqueue();
        Async.setMock(mock);
        mock.threads.service.isFinalizer = true;
        mock.threads.queries.pendingThreads.add(new Thread__c(Status__c = Thread.PENDING));

        Thread.enqueue();

        Assert.areEqual(0, mock.threads.service.startCalls,
            'Expected Thread.enqueue to avoid spawning threads from finalizer context.');
    }

    @istest static void testWake_startsRequestedPoolWithoutCreatingAsyncThread() {
        ThreadMock mock = new ThreadMock()
            .canEnqueue();
        Thread.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
        Thread__c eventThread = thread(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        insert eventThread;
        mock.queries.pendingThreads.add(eventThread);

        Thread.wake(EventRelay.PUBLISH_POOL);

        Assert.areEqual(1, mock.service.startCalls,
            'Expected Thread.wake to start pending work in the requested pool.');
        Assert.areEqual(eventThread.Id, mock.service.startedThreads[0],
            'Expected Thread.wake to start the EventRelay publish thread.');
        Assert.areEqual(eventThread.Id, Thread.currentId(),
            'Expected Thread.wake to adopt the started EventRelay thread.');
    }

    @istest static void testClaimNextLeavesPendingThreadWhenSlotFillsBeforeStatusUpdate() {
        AsyncMock mock = new AsyncMock();
        Async.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 1));
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
            .mockThreadIds();
        Async.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 1));
        mock.threads.runningThreads(1);

        Thread.enqueue();

        Assert.areEqual(0, mock.threads.service.startCalls, 'Expected Thread.enqueue to leave pending work alone when the user is at the thread cap.');
        Assert.areEqual(null, Thread.currentId(), 'Expected Thread.enqueue not to create a new thread when no slot is available.');
    }

    @istest static void testContinueCurrent_doesNotClaimNextThreadWhenCapIsFull() {
        ThreadMock mock = new ThreadMock()
            .runningThreads(1);
        Thread.setMock(mock);
        Id threadId = Thread.currentOrCreate();
        String runKey = Thread.service.startRun(threadId);
        Thread__c nextThread = new Thread__c(Status__c = Thread.PENDING);
        insert nextThread;
        mock.queries.pendingThreads.add(nextThread);
        Async.queries = new EmptyWorkQueryService();
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 1));

        Thread.continueCurrent(runKey);

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

    @istest static void testSettingsService_defaultsThreadRecoveryValues() {
        Thread.SettingsService settings = new Thread.SettingsService();
        settings.setSettings(new Thread_Settings__c());

        Assert.areEqual(1, settings.maxThreads(), 'Expected Thread max threads to default to one global slot.');
        Assert.areEqual(10, settings.recoveryThresholdMinutes(), 'Expected recovery threshold to default to ten minutes.');
        Assert.areEqual(10, settings.recoveryBatchSize(), 'Expected recovery batch size to default to ten stale threads.');
        Assert.areEqual(90, settings.recoveryLimitThresholdPct(), 'Expected recovery limiter threshold to default to ninety percent.');
        Assert.isTrue(settings.recoveryEnabled(), 'Expected Thread recovery to default on.');
    }

    @istest static void testQueryService_getRecoverableThreadsLocksOrderedCandidates() {
        DateTime now = System.now();
        Thread__c doneThread = staleThread('done');
        doneThread.Status__c = Thread.DONE;
        doneThread.Heartbeat__c = now.addMinutes(-40);
        Thread__c oldestThread = staleThread('oldest');
        oldestThread.Heartbeat__c = now.addMinutes(-30);
        Thread__c newerThread = staleThread('newer');
        newerThread.Heartbeat__c = now.addMinutes(-20);
        Thread__c extraThread = staleThread('extra');
        extraThread.Heartbeat__c = now.addMinutes(-10);
        insert new List<Thread__c> { doneThread, newerThread, oldestThread, extraThread };

        List<Thread__c> recoverableThreads = new Thread.QueryService().getRecoverableThreads(now.addMinutes(-5), 2);

        Assert.areEqual(2, recoverableThreads.size(), 'Expected recovery to lock only the configured number of stale active threads.');
        Assert.areEqual(oldestThread.Id, recoverableThreads[0].Id, 'Expected recovery to preserve oldest heartbeat ordering after locking.');
        Assert.areEqual(newerThread.Id, recoverableThreads[1].Id, 'Expected recovery to return the next-oldest stale thread after locking.');
    }

    @istest static void testCreate_stampsInitialHeartbeat() {
        Thread.setMock(new ThreadMock());

        Id threadId = Thread.currentOrCreate();

        Thread__c threadRecord = [
            SELECT Heartbeat__c
            FROM Thread__c
            WHERE Id = :threadId
        ];
        Assert.isNotNull(threadRecord.Heartbeat__c, 'Expected new threads to have an initial heartbeat for recovery age checks.');
    }

    @istest static void testStartRun_stampsLifecycleAndRunKey() {
        Thread__c threadRecord = thread(Thread.ASYNC_POOL, 'request:start');
        insert threadRecord;

        String runKey = Thread.service.startRun(threadRecord.Id);

        Thread__c storedThread = [
            SELECT Status__c, Started__c, Completed__c, Heartbeat__c, Run_Key__c
            FROM Thread__c
            WHERE Id = :threadRecord.Id
        ];
        Assert.areEqual(Thread.RUNNING, storedThread.Status__c, 'Expected starting a thread run to mark it Running.');
        Assert.isNotNull(storedThread.Started__c, 'Expected starting a thread run to stamp Started.');
        Assert.isNotNull(storedThread.Heartbeat__c, 'Expected starting a thread run to refresh Heartbeat.');
        Assert.areEqual(null, storedThread.Completed__c, 'Expected starting a thread run to clear Completed.');
        Assert.areEqual(runKey, storedThread.Run_Key__c, 'Expected starting a thread run to persist the generated run key.');
    }

    @istest static void testContinueCurrent_staleRunKeyDoesNotAdvanceThread() {
        ThreadMock mock = new ThreadMock();
        Thread.setMock(mock);
        Thread__c threadRecord = thread(Thread.ASYNC_POOL, 'request:stale');
        insert threadRecord;
        Thread.setCurrent(threadRecord.Id);
        Thread.service.startRun(threadRecord.Id);
        Async.queries = new PendingWorkQueryService();

        Thread.continueCurrent('stale-run-key');

        Assert.areEqual(0, mock.service.continueWorkCalls, 'Expected a stale run key not to continue current work.');
        Assert.areEqual(0, mock.service.startCalls, 'Expected a stale run key not to restart the thread.');
    }

    @istest static void testRecover_restartsRecoverableThreadWithAdvancedRunKey() {
        Limiter.setMock(new LimiterMock().setLimit(Limiter.types.QUEUEABLE_JOBS, 0, 50));
        ThreadMock mock = new ThreadMock()
            .seedSettings(new Thread_Settings__c(Max_Threads__c = 2));
        Thread.setMock(mock);
        Thread__c staleThread = staleThread('recoverable');
        insert staleThread;
        mock.queries.recoverableThreads.add(staleThread);
        SpyDispatcher dispatcher = new SpyDispatcher();
        dispatcher.hasRecoverableWork = true;
        SpyRunnerService runner = new SpyRunnerService(dispatcher);
        ThreadRunner.setMock(runner);

        Thread.recover();

        Thread__c recoveredThread = [
            SELECT Status__c, Run_Key__c, Heartbeat__c
            FROM Thread__c
            WHERE Id = :staleThread.Id
        ];
        Assert.areEqual(Thread.RUNNING, recoveredThread.Status__c, 'Expected recovery to leave recoverable work Running for the replacement chain.');
        Assert.areNotEqual('old-run-key', recoveredThread.Run_Key__c, 'Expected recovery to advance the run key before restart.');
        Assert.isNotNull(recoveredThread.Heartbeat__c, 'Expected recovery to refresh the stale heartbeat.');
        Assert.areEqual(1, dispatcher.prepareRecoveryCalls, 'Expected recovery to let the dispatcher prepare stranded work.');
        Assert.areEqual(1, runner.startCalls, 'Expected recovery to restart recoverable work through ThreadRunner.');
        Assert.areEqual(recoveredThread.Run_Key__c, runner.lastRunKey, 'Expected the replacement runner to carry the newly authorized run key.');
    }

    @istest static void testRecover_completesStaleThreadWithNoRecoverableWork() {
        Limiter.setMock(new LimiterMock().setLimit(Limiter.types.QUEUEABLE_JOBS, 0, 50));
        ThreadMock mock = new ThreadMock()
            .seedSettings(new Thread_Settings__c(Max_Threads__c = 2));
        Thread.setMock(mock);
        Thread__c staleThread = staleThread('empty');
        insert staleThread;
        mock.queries.recoverableThreads.add(staleThread);
        SpyRunnerService runner = new SpyRunnerService(new SpyDispatcher());
        ThreadRunner.setMock(runner);

        Thread.recover();

        Thread__c completedThread = [
            SELECT Status__c, Completed__c
            FROM Thread__c
            WHERE Id = :staleThread.Id
        ];
        Assert.areEqual(Thread.DONE, completedThread.Status__c, 'Expected recovery to complete stale threads with no recoverable work.');
        Assert.isNotNull(completedThread.Completed__c, 'Expected recovery completion to stamp Completed.');
        Assert.areEqual(0, runner.startCalls, 'Expected recovery not to start a replacement chain when no work remains.');
    }

    @istest static void testRecover_doesNothingWhenRecoveryDisabled() {
        Limiter.setMock(new LimiterMock().setLimit(Limiter.types.QUEUEABLE_JOBS, 0, 50));
        ThreadMock mock = new ThreadMock()
            .seedSettings(new Thread_Settings__c(Enable_Recovery__c = false, Max_Threads__c = 2));
        Thread.setMock(mock);
        Thread__c staleThread = staleThread('disabled');
        insert staleThread;
        mock.queries.recoverableThreads.add(staleThread);
        SpyDispatcher dispatcher = new SpyDispatcher();
        dispatcher.hasRecoverableWork = true;
        SpyRunnerService runner = new SpyRunnerService(dispatcher);
        ThreadRunner.setMock(runner);

        Thread.recover();

        Thread__c untouchedThread = [
            SELECT Status__c, Run_Key__c
            FROM Thread__c
            WHERE Id = :staleThread.Id
        ];
        Assert.areEqual(Thread.RUNNING, untouchedThread.Status__c, 'Expected disabled recovery to leave stale threads untouched.');
        Assert.areEqual('old-run-key', untouchedThread.Run_Key__c, 'Expected disabled recovery not to fence the existing run key.');
        Assert.areEqual(0, runner.startCalls, 'Expected disabled recovery not to start a replacement chain.');
    }

    @istest static void testRecover_doesNothingWhenLimiterIsUnsafe() {
        Limiter.setMock(new LimiterMock().setLimit(Limiter.types.QUEUEABLE_JOBS, 90, 100));
        ThreadMock mock = new ThreadMock()
            .seedSettings(new Thread_Settings__c(Max_Threads__c = 2, Recovery_Limit_Threshold_Pct__c = 90));
        Thread.setMock(mock);
        Thread__c staleThread = staleThread('unsafe');
        insert staleThread;
        mock.queries.recoverableThreads.add(staleThread);
        SpyDispatcher dispatcher = new SpyDispatcher();
        dispatcher.hasRecoverableWork = true;
        SpyRunnerService runner = new SpyRunnerService(dispatcher);
        ThreadRunner.setMock(runner);

        Thread.recover();

        Thread__c untouchedThread = [
            SELECT Run_Key__c
            FROM Thread__c
            WHERE Id = :staleThread.Id
        ];
        Assert.areEqual('old-run-key', untouchedThread.Run_Key__c, 'Expected unsafe limiter state not to advance the stale run key.');
        Assert.areEqual(0, runner.startCalls, 'Expected unsafe limiter state not to start a replacement chain.');
    }

    @istest static void testReopen_marksDoneThreadPending() {
        Thread__c drainedThread = thread('EventRelayPublish', 'Bedrock_Test_Event__e');
        drainedThread.Status__c = Thread.DONE;
        drainedThread.Completed__c = System.now();
        drainedThread.Run_Key__c = 'old-run-key';
        insert drainedThread;

        Thread.reopen(new Set<Id> { drainedThread.Id });

        Thread__c reopenedThread = [
            SELECT Status__c, Completed__c, Run_Key__c
            FROM Thread__c
            WHERE Id = :drainedThread.Id
        ];
        Assert.areEqual(Thread.PENDING, reopenedThread.Status__c,
            'Expected appending new lane work to reopen a drained thread for dispatch.');
        Assert.isNull(reopenedThread.Completed__c,
            'Expected reopened threads to clear their completed timestamp.');
        Assert.isNull(reopenedThread.Run_Key__c,
            'Expected reopened threads to clear their old run key.');
    }

    public with sharing class EmptyWorkQueryService extends Async.QueryService {
        public override Boolean hasPendingWork(Id threadId) {
            return false;
        }
    }

    public with sharing class EmptyEventWorkQueryService extends EventRelay.QueryService {
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

        public override void enqueueNextJob(Id threadId, Integer failures, String runKey) {
            this.lastThreadId = threadId;
            this.lastFailures = failures;
        }
    }

    public with sharing class SpyRunnerService extends ThreadRunner.Service {
        public SpyDispatcher dispatcher;
        public Integer startCalls = 0;
        public Id lastThreadId;
        public Integer lastFailures;
        public String lastRunKey;

        public SpyRunnerService(SpyDispatcher dispatcher) {
            this.dispatcher = dispatcher;
        }

        public override void start(Id threadId, Integer failures, String runKey) {
            this.startCalls++;
            this.lastThreadId = threadId;
            this.lastFailures = failures;
            this.lastRunKey = runKey;
        }

        public override ThreadRunner.Dispatcher dispatcherForPool(String pool) {
            return this.dispatcher;
        }
    }

    public with sharing class SpyDispatcher extends ThreadRunner.Dispatcher {
        public Boolean hasRecoverableWork = false;
        public Integer prepareRecoveryCalls = 0;

        public override Boolean hasRecoverableWork(Id threadId) {
            return this.hasRecoverableWork;
        }

        public override void prepareRecovery(Id threadId) {
            this.prepareRecoveryCalls++;
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

    static Thread__c staleThread(String threadKey) {
        Thread__c threadRecord = thread(Thread.ASYNC_POOL, threadKey);
        threadRecord.Status__c = Thread.RUNNING;
        threadRecord.Heartbeat__c = System.now().addMinutes(-30);
        threadRecord.Run_Key__c = 'old-run-key';
        return threadRecord;
    }

    public class NoOpQueueable implements Queueable {
        public void execute(QueueableContext context) {
        }
    }

    public class NoOpAsync extends Async {
        public override void execute(Set<Id> ids) {
        }
    }
}
