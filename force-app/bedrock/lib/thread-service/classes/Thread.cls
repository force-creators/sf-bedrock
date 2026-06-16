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

    public static Id currentOrCreate(String pool, String threadKey) {
        return service.currentOrCreate(pool, threadKey);
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
        Map<String, Id> threadIdsByUniqueKey = new Map<String, Id>();
        String defaultThreadKey;

        public virtual Id currentId() {
            return threadId;
        }

        public virtual Id currentOrCreate() {
            return currentOrCreate(ASYNC_POOL, requestThreadKey());
        }

        public virtual Id currentOrCreate(String pool, String threadKey) {
            String normalizedPool = normalizePool(pool);
            String normalizedThreadKey = normalizeThreadKey(threadKey);
            String uniqueKey = uniqueKey(normalizedPool, normalizedThreadKey);

            if (!threadIdsByUniqueKey.containsKey(uniqueKey)) {
                Thread__c existingThread = queries.getThreadByUniqueKey(uniqueKey);
                threadIdsByUniqueKey.put(
                    uniqueKey,
                    existingThread == null ? create(normalizedPool, normalizedThreadKey, uniqueKey) : existingThread.Id
                );
            }
            threadId = threadIdsByUniqueKey.get(uniqueKey);
            return threadId;
        }

        public virtual Id create() {
            return create(ASYNC_POOL, requestThreadKey());
        }

        public virtual Id create(String pool, String threadKey) {
            String normalizedPool = normalizePool(pool);
            String normalizedThreadKey = normalizeThreadKey(threadKey);
            return create(normalizedPool, normalizedThreadKey, uniqueKey(normalizedPool, normalizedThreadKey));
        }

        Id create(String pool, String threadKey, String uniqueKey) {
            Thread__c thread = new Thread__c(
                Status__c = PENDING,
                Pool__c = pool,
                Thread_Key__c = threadKey,
                Unique_Key__c = uniqueKey
            );
            DML.insertRecords(new List<SObject> { thread });
            return thread.Id;
        }

        public virtual void setCurrent(Id threadId) {
            this.threadId = threadId;
        }

        public virtual void enqueue() {
            if (!canEnqueue() || hasEnqueued || System.isQueueable() || isFinalizer) return;
            if (!hasAvailableSlot()) return;

            currentOrCreate();
            Id nextThreadId = claimNext(currentPool());
            if (nextThreadId == null) return;

            setCurrent(nextThreadId);
            start(nextThreadId, 0);
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
            Id nextThreadId = claimNext(currentPool());
            if (nextThreadId == null) return;

            setCurrent(nextThreadId);
            start(nextThreadId, 0);
        }

        public virtual void continueWork(Id threadId, Integer failures) {
            ThreadRunner.service.dispatch(threadId, failures);
        }

        public virtual void start(Id threadId, Integer failures) {
            ThreadRunner.service.start(threadId, failures);
        }

        public virtual Boolean hasCurrentWork() {
            return currentId() != null && ThreadRunner.service.hasPendingWork(currentId());
        }

        public virtual Id claimNext() {
            return claimNext(ASYNC_POOL);
        }

        public virtual Id claimNext(String pool) {
            if (!hasAvailableSlot(pool)) return null;

            Thread__c thread = queries.getNextPendingThread(pool);
            if (thread == null) return null;
            if (!hasAvailableSlot(pool)) return null;

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
            return hasAvailableSlot(ASYNC_POOL);
        }

        public virtual Boolean hasAvailableSlot(String pool) {
            return runningThreadCount(pool) < maxThreads(pool);
        }

        public virtual Integer runningThreadCount() {
            return runningThreadCount(ASYNC_POOL);
        }

        public virtual Integer runningThreadCount(String pool) {
            return queries.countRunningThreads(UserInfo.getUserId(), pool);
        }

        public virtual Integer maxThreads() {
            return maxThreads(ASYNC_POOL);
        }

        public virtual Integer maxThreads(String pool) {
            return ThreadRunner.service.maxThreads(pool);
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

        String requestThreadKey() {
            if (defaultThreadKey != null) return defaultThreadKey;
            try {
                defaultThreadKey = 'request:' + Request.getCurrent().getRequestId();
            } catch (Exception error) {
                defaultThreadKey = 'generated:' + String.valueOf(Crypto.getRandomInteger());
            }
            return defaultThreadKey;
        }

        String normalizePool(String pool) {
            return String.isBlank(pool) ? ASYNC_POOL : pool.trim();
        }

        String normalizeThreadKey(String threadKey) {
            return String.isBlank(threadKey) ? requestThreadKey() : threadKey.trim();
        }

        String currentPool() {
            Thread__c threadRecord = queries.getThread(currentId());
            return threadRecord == null || String.isBlank(threadRecord.Pool__c)
                ? ASYNC_POOL
                : threadRecord.Pool__c;
        }

        String uniqueKey(String pool, String threadKey) {
            Blob digest = Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(normalizePool(pool) + ':' + normalizeThreadKey(threadKey))
            );
            return EncodingUtil.convertToHex(digest);
        }
    }

    public virtual with sharing class QueryService {
        public virtual Thread__c getThread(Id threadId) {
            if (threadId == null) return null;

            List<Thread__c> threads = (List<Thread__c>) Query.records([
                SELECT Id, Pool__c, Thread_Key__c, Unique_Key__c, Status__c
                FROM Thread__c
                WHERE Id = :threadId
                LIMIT 1
            ]);
            return threads.isEmpty() ? null : threads[0];
        }

        public virtual Thread__c getThreadByUniqueKey(String uniqueKey) {
            if (String.isBlank(uniqueKey)) return null;

            List<Thread__c> threads = (List<Thread__c>) Query.records([
                SELECT Id, Pool__c, Thread_Key__c, Unique_Key__c, Status__c
                FROM Thread__c
                WHERE Unique_Key__c = :uniqueKey
                LIMIT 1
                FOR UPDATE
            ]);
            return threads.isEmpty() ? null : threads[0];
        }

        public virtual Thread__c getNextPendingThread() {
            return getNextPendingThread(ASYNC_POOL);
        }

        public virtual Thread__c getNextPendingThread(String pool) {
            String normalizedPool = String.isBlank(pool) ? ASYNC_POOL : pool.trim();
            Id userId = UserInfo.getUserId();
            List<Thread__c> candidates;
            if (normalizedPool == ASYNC_POOL) {
                candidates = (List<Thread__c>) Query.records([
                    SELECT Id
                    FROM Thread__c
                    WHERE Status__c = 'Pending'
                        AND CreatedById = :userId
                        AND (Pool__c = :normalizedPool OR Pool__c = null)
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ]);
            } else {
                candidates = (List<Thread__c>) Query.records([
                    SELECT Id
                    FROM Thread__c
                    WHERE Status__c = 'Pending'
                        AND CreatedById = :userId
                        AND Pool__c = :normalizedPool
                    ORDER BY CreatedDate ASC
                    LIMIT 1
                ]);
            }
            if (candidates.isEmpty()) return null;

            List<Thread__c> threads = (List<Thread__c>) Query.records([
                SELECT Id, Pool__c, Status__c
                FROM Thread__c
                WHERE Id = :candidates[0].Id
                    AND Status__c = 'Pending'
                FOR UPDATE
            ]);
            return threads.isEmpty() ? null : threads[0];
        }

        public virtual Integer countRunningThreads(Id userId) {
            return countRunningThreads(userId, ASYNC_POOL);
        }

        public virtual Integer countRunningThreads(Id userId, String pool) {
            String normalizedPool = String.isBlank(pool) ? ASYNC_POOL : pool.trim();
            if (normalizedPool == ASYNC_POOL) {
                return [
                    SELECT COUNT()
                    FROM Thread__c
                    WHERE Status__c = 'Running'
                        AND CreatedById = :userId
                        AND (Pool__c = :normalizedPool OR Pool__c = null)
                ];
            }

            return [
                SELECT COUNT()
                FROM Thread__c
                WHERE Status__c = 'Running'
                    AND CreatedById = :userId
                    AND Pool__c = :normalizedPool
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
