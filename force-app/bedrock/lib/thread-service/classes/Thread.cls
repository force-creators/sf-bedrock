public virtual with sharing class Thread {
    public static final String ASYNC_POOL = 'Async';
    public static final String DONE = 'Done';
    public static final String PENDING = 'Pending';
    public static final String RUNNING = 'Running';

    public static Service service = new Service();
    public static QueryService queries = new QueryService();

    @testVisible public static void setMock(ThreadMock mock) {
        service = mock.service;
        queries = mock.queries;
    }

    @testVisible public static void reset() {
        service = new Service();
        queries = new QueryService();
    }

    public static Id currentId() {
        return service.currentId();
    }

    public static Id currentOrCreate() {
        return service.currentOrCreate();
    }

    public static void setCurrent(Id threadId) {
        service.setCurrent(threadId);
    }

    public static void enqueue() {
        service.enqueue();
    }

    public static void continueCurrent() {
        service.continueCurrent();
    }

    public static void continueCurrent(Integer failures) {
        service.continueCurrent(failures);
    }

    public static void deleteDrained(Set<Id> threadIds) {
        service.deleteDrained(threadIds);
    }

    public virtual with sharing class Service {
        public Id threadId;
        public Boolean hasEnqueued = false;
        public Boolean isFinalizer = false;
        public Integer restartLimit = 4;

        public virtual Id currentId() {
            return threadId;
        }

        public virtual Id currentOrCreate() {
            if (threadId == null) {
                threadId = create();
            }
            return threadId;
        }

        public virtual Id create() {
            Thread__c thread = new Thread__c(Status__c = PENDING);
            DML.insertRecords(new List<SObject> { thread });
            return thread.Id;
        }

        public virtual void setCurrent(Id threadId) {
            this.threadId = threadId;
        }

        public virtual void enqueue() {
            if (!canEnqueue() || hasEnqueued || System.isQueueable() || isFinalizer) return;
            if (!hasAvailableSlot()) return;

            start(currentOrCreate(), 0);
            hasEnqueued = true;
        }

        public virtual void continueCurrent() {
            continueCurrent(0);
        }

        public virtual void continueCurrent(Integer failures) {
            Integer safeFailures = failures == null ? 0 : failures;
            if (hasCurrentWork()) {
                if (shouldRestartThread(safeFailures)) {
                    start(currentId(), 0);
                    return;
                }

                continueWork(currentId(), safeFailures);
                return;
            }

            complete(currentId());
            Id nextThreadId = claimNext();
            if (nextThreadId == null) return;

            setCurrent(nextThreadId);
            start(nextThreadId, 0);
        }

        public virtual void continueWork(Id threadId, Integer failures) {
            Async.jobs.enqueueNextJob(threadId, failures);
        }

        public virtual void start(Id threadId, Integer failures) {
            if (threadId == null) return;

            running(threadId);
            System.enqueueJob(new AsyncThread(threadId, failures));
        }

        public virtual Boolean hasCurrentWork() {
            return currentId() != null && Async.queries.hasPendingWork(currentId());
        }

        public virtual Id claimNext() {
            if (!hasAvailableSlot()) return null;

            Thread__c thread = queries.getNextPendingThread();
            if (thread == null) return null;

            running(thread.Id);
            return thread.Id;
        }

        public virtual void running(Id threadId) {
            updateStatus(threadId, RUNNING);
        }

        public virtual void complete(Id threadId) {
            updateStatus(threadId, DONE);
        }

        public virtual Boolean shouldRestartThread(Integer failures) {
            Integer safeFailures = failures == null ? 0 : failures;
            return safeFailures >= restartLimit;
        }

        public virtual Boolean hasAvailableSlot() {
            return runningThreadCount() < maxThreads();
        }

        public virtual Integer runningThreadCount() {
            return queries.countRunningThreads(UserInfo.getUserId());
        }

        public virtual Integer maxThreads() {
            return Async.settings.maxThreads();
        }

        public virtual Boolean canEnqueue() {
            return !Test.isRunningTest();
        }

        public virtual void deleteDrained(Set<Id> threadIds) {
            if (threadIds == null || threadIds.isEmpty()) return;

            Set<Id> drainedThreadIds = new Set<Id>(threadIds);
            drainedThreadIds.remove(null);
            if (drainedThreadIds.isEmpty()) return;

            drainedThreadIds.removeAll(queries.getThreadIdsWithAsyncWork(drainedThreadIds));
            if (drainedThreadIds.isEmpty()) return;

            List<SObject> threads = new List<SObject>();
            for (Id threadId : drainedThreadIds) {
                threads.add(new Thread__c(Id = threadId));
            }

            DML.deleteRecords(threads);
        }

        void updateStatus(Id threadId, String status) {
            if (threadId == null || String.isBlank(status)) return;

            DML.updateRecords(new List<SObject> {
                new Thread__c(
                    Id = threadId,
                    Status__c = status
                )
            });
        }
    }

    public virtual with sharing class QueryService {
        public virtual Thread__c getNextPendingThread() {
            Id userId = UserInfo.getUserId();
            List<Thread__c> candidates = (List<Thread__c>) Query.records([
                SELECT Id
                FROM Thread__c
                WHERE Status__c = 'Pending'
                    AND CreatedById = :userId
                ORDER BY CreatedDate ASC
                LIMIT 1
            ]);
            if (candidates.isEmpty()) return null;

            List<Thread__c> threads = (List<Thread__c>) Query.records([
                SELECT Id, Status__c
                FROM Thread__c
                WHERE Id = :candidates[0].Id
                    AND Status__c = 'Pending'
                FOR UPDATE
            ]);
            return threads.isEmpty() ? null : threads[0];
        }

        public virtual Integer countRunningThreads(Id userId) {
            return [
                SELECT COUNT()
                FROM Thread__c
                WHERE Status__c = 'Running'
                    AND CreatedById = :userId
            ];
        }

        public virtual Set<Id> getThreadIdsWithAsyncWork(Set<Id> threadIds) {
            if (threadIds == null || threadIds.isEmpty()) return new Set<Id>();

            Set<Id> activeThreadIds = new Set<Id>();
            for (AggregateResult result : [
                SELECT Thread__c threadId
                FROM Async__c
                WHERE Thread__c IN :threadIds
                GROUP BY Thread__c
            ]) {
                activeThreadIds.add((Id) result.get('threadId'));
            }
            return activeThreadIds;
        }
    }
}
