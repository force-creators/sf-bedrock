public virtual with sharing class Thread {
    public static final String ASYNC_POOL = 'Async';
    public static final String DONE = 'Done';
    public static final String PENDING = 'Pending';
    public static final String RUNNING = 'Running';

    public static Service service = new Service();
    public static QueryService queries = new QueryService();
    public static SettingsService settings = new SettingsService();

    @testVisible public static void setMock(ThreadMock mock) {
        service = mock.service;
        queries = mock.queries;
        settings = mock.settings;
    }

    @testVisible public static void reset() {
        service = new Service();
        queries = new QueryService();
        settings = new SettingsService();
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

    public static void wake(String pool) {
        service.wake(pool);
    }

    public static void continueCurrent() {
        service.continueCurrent();
    }

    public static void continueCurrent(Integer failures) {
        service.continueCurrent(failures);
    }

    public static void continueCurrent(String runKey) {
        service.continueCurrent(0, runKey);
    }

    public static void continueCurrent(Integer failures, String runKey) {
        service.continueCurrent(failures, runKey);
    }

    public static void recover() {
        service.recover();
    }

    public static void reopen(Set<Id> threadIds) {
        service.reopen(threadIds);
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
                Unique_Key__c = uniqueKey,
                Heartbeat__c = System.now()
            );
            DML.insertRecords(new List<SObject> { thread });
            return thread.Id;
        }

        public virtual void setCurrent(Id threadId) {
            this.threadId = threadId;
        }

        public virtual void enqueue() {
            if (!canEnqueue() || hasEnqueued || System.isQueueable() || isFinalizer) return;

            fillAvailableSlots();
        }

        public virtual void fillAvailableSlots() {
            Integer spawnCount = availableSpawnCount();
            if (spawnCount < 1) return;

            if (currentId() == null) currentOrCreate();
            fillAvailableSlots(currentPool(), spawnCount);
        }

        public virtual void wake(String pool) {
            if (!canEnqueue() || hasEnqueued || System.isQueueable() || isFinalizer) return;

            fillAvailableSlots(pool);
        }

        public virtual void fillAvailableSlots(String pool) {
            Integer spawnCount = availableSpawnCount(pool);
            if (spawnCount < 1) return;

            fillAvailableSlots(pool, spawnCount);
        }

        void fillAvailableSlots(String pool, Integer spawnCount) {
            for (Integer i = 0; i < spawnCount; i++) {
                Id nextThreadId = claimNext(pool);
                if (nextThreadId == null) return;

                setCurrent(nextThreadId);
                start(nextThreadId, 0);
                hasEnqueued = true;
            }
        }

        public virtual void continueCurrent() {
            continueCurrent(0);
        }

        public virtual void continueCurrent(Integer failures) {
            continueCurrent(failures, currentRunKey(currentId()));
        }

        public virtual void continueCurrent(Integer failures, String runKey) {
            Integer safeFailures = failures == null ? 0 : failures;
            if (!isRunAuthorized(currentId(), runKey)) return;

            heartbeat(currentId());
            if (hasCurrentWork()) {
                if (shouldRestartThread(safeFailures)) {
                    start(currentId(), 0);
                    return;
                }

                continueWork(currentId(), safeFailures);
                return;
            }

            String drainedPool = currentPool();
            complete(currentId());
            Id nextThreadId = ThreadRunner.service.claimNextAfterDrain(drainedPool);
            if (nextThreadId == null) return;

            setCurrent(nextThreadId);
            start(nextThreadId, 0);
        }

        public virtual void continueWork(Id threadId, Integer failures) {
            ThreadRunner.service.dispatch(threadId, failures, currentRunKey(threadId));
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
            startRun(threadId);
        }

        public virtual void complete(Id threadId) {
            complete(threadId, currentRunKey(threadId));
        }

        public virtual void complete(Id threadId, String runKey) {
            if (!isRunAuthorized(threadId, runKey)) return;

            updateThread(new Thread__c(
                Id = threadId,
                Status__c = DONE,
                Completed__c = System.now(),
                Heartbeat__c = System.now()
            ));
        }

        public virtual String startRun(Id threadId) {
            if (threadId == null) return null;

            String runKey = generateRunKey();
            updateThread(new Thread__c(
                Id = threadId,
                Status__c = RUNNING,
                Started__c = System.now(),
                Completed__c = null,
                Heartbeat__c = System.now(),
                Run_Key__c = runKey
            ));
            return runKey;
        }

        public virtual void heartbeat(Id threadId) {
            if (threadId == null) return;

            updateThread(new Thread__c(
                Id = threadId,
                Heartbeat__c = System.now()
            ));
        }

        public virtual Boolean isRunAuthorized(Id threadId, String runKey) {
            if (threadId == null || String.isBlank(runKey)) return false;

            Thread__c thread = queries.getThread(threadId);
            return thread != null && thread.Run_Key__c == runKey;
        }

        public virtual String currentRunKey(Id threadId) {
            Thread__c thread = queries.getThread(threadId);
            return thread == null ? null : thread.Run_Key__c;
        }

        public virtual Boolean shouldRestartThread(Integer failures) {
            Integer safeFailures = failures == null ? 0 : failures;
            return safeFailures >= restartLimit;
        }

        public virtual Boolean hasAvailableSlot() {
            return hasAvailableSlot(ASYNC_POOL);
        }

        public virtual Boolean hasAvailableSlot(String pool) {
            return runningThreadCount(pool) < maxThreads(pool)
                && globalRunningThreadCount() < Thread.settings.maxThreads();
        }

        public virtual Integer availableSpawnCount() {
            return availableSpawnCount(ASYNC_POOL);
        }

        public virtual Integer availableSpawnCount(String pool) {
            Integer availableThreadSlots = maxThreads(pool) - runningThreadCount(pool);
            Integer availableGlobalSlots = Thread.settings.maxThreads() - globalRunningThreadCount();
            Integer availableQueueableSlots = Limits.getLimitQueueableJobs() - Limits.getQueueableJobs();
            return Math.max(0, Math.min(Math.min(availableThreadSlots, availableGlobalSlots), availableQueueableSlots));
        }

        public virtual Integer runningThreadCount() {
            return runningThreadCount(ASYNC_POOL);
        }

        public virtual Integer runningThreadCount(String pool) {
            return isUserScoped(pool)
                ? queries.countRunningThreads(UserInfo.getUserId(), pool)
                : queries.countRunningThreads(pool);
        }

        public virtual Integer globalRunningThreadCount() {
            return queries.countRunningThreads();
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

        public virtual void recover() {
            if (!Thread.settings.recoveryEnabled()) return;
            if (!Limiter.isSafe(Limiter.types.QUEUEABLE_JOBS, Thread.settings.recoveryLimitThresholdPct())) return;

            DateTime staleBefore = System.now().addMinutes(-Thread.settings.recoveryThresholdMinutes());
            for (Thread__c staleThread : queries.getRecoverableThreads(staleBefore, Thread.settings.recoveryBatchSize())) {
                recover(staleThread);
            }
        }

        public virtual void recover(Thread__c staleThread) {
            if (staleThread == null || staleThread.Id == null || staleThread.Status__c == DONE) return;
            if (!Thread.settings.recoveryEnabled()) return;
            if (!Limiter.isSafe(Limiter.types.QUEUEABLE_JOBS, Thread.settings.recoveryLimitThresholdPct())) return;
            if (!hasRecoverySlot(staleThread)) return;

            ThreadRunner.Dispatcher dispatcher = ThreadRunner.service.dispatcherForPool(staleThread.Pool__c);
            String runKey = startRun(staleThread.Id);
            dispatcher.prepareRecovery(staleThread.Id);

            if (dispatcher.hasRecoverableWork(staleThread.Id)) {
                ThreadRunner.service.start(staleThread.Id, 0, runKey);
                return;
            }

            complete(staleThread.Id, runKey);
        }

        public virtual void reopen(Set<Id> threadIds) {
            if (threadIds == null || threadIds.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            for (Thread__c threadRecord : queries.getThreadsForUpdate(threadIds)) {
                if (threadRecord.Status__c != DONE) continue;

                updates.add(new Thread__c(
                    Id = threadRecord.Id,
                    Status__c = PENDING,
                    Completed__c = null,
                    Heartbeat__c = System.now(),
                    Run_Key__c = null
                ));
            }
            if (!updates.isEmpty()) DML.updateRecords(updates);
        }

        Boolean hasRecoverySlot(Thread__c threadRecord) {
            String pool = threadRecord == null ? ASYNC_POOL : threadRecord.Pool__c;
            Id threadId = threadRecord == null ? null : threadRecord.Id;
            return runningThreadCountExcluding(pool, threadId) < maxThreads(pool)
                && queries.countRunningThreadsExcluding(threadId) < Thread.settings.maxThreads()
                && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs();
        }

        Integer runningThreadCountExcluding(String pool, Id excludedThreadId) {
            return isUserScoped(pool)
                ? queries.countRunningThreadsExcluding(UserInfo.getUserId(), pool, excludedThreadId)
                : queries.countRunningThreadsExcluding(pool, excludedThreadId);
        }

        Boolean isUserScoped(String pool) {
            return !EventRelay.isEventPool(normalizePool(pool));
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

            updateThread(new Thread__c(
                Id = threadId,
                Status__c = status
            ));
        }

        void updateThread(Thread__c threadRecord) {
            if (threadRecord == null || threadRecord.Id == null) return;

            DML.updateRecords(new List<SObject> { threadRecord });
        }

        String generateRunKey() {
            Blob digest = Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(String.valueOf(Crypto.getRandomInteger()) + ':' + String.valueOf(System.now().getTime()))
            );
            return EncodingUtil.convertToHex(digest);
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
                SELECT Id, Pool__c, Thread_Key__c, Unique_Key__c, Status__c, Run_Key__c, Heartbeat__c
                FROM Thread__c
                WHERE Id = :threadId
                LIMIT 1
            ]);
            return threads.isEmpty() ? null : threads[0];
        }

        public virtual Thread__c getThreadByUniqueKey(String uniqueKey) {
            if (String.isBlank(uniqueKey)) return null;

            List<Thread__c> threads = (List<Thread__c>) Query.records([
                SELECT Id, Pool__c, Thread_Key__c, Unique_Key__c, Status__c, Run_Key__c, Heartbeat__c
                FROM Thread__c
                WHERE Unique_Key__c = :uniqueKey
                LIMIT 1
                FOR UPDATE
            ]);
            return threads.isEmpty() ? null : threads[0];
        }

        public virtual List<Thread__c> getThreadsForUpdate(Set<Id> threadIds) {
            if (threadIds == null || threadIds.isEmpty()) return new List<Thread__c>();

            return (List<Thread__c>) Query.records([
                SELECT Id, Status__c
                FROM Thread__c
                WHERE Id IN :threadIds
                FOR UPDATE
            ]);
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
            } else if (EventRelay.isEventPool(normalizedPool)) {
                candidates = (List<Thread__c>) Query.records([
                    SELECT Id
                    FROM Thread__c
                    WHERE Status__c = 'Pending'
                        AND Pool__c = :normalizedPool
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
                SELECT Id, Pool__c, Status__c, Run_Key__c, Heartbeat__c
                FROM Thread__c
                WHERE Id = :candidates[0].Id
                    AND Status__c = 'Pending'
                FOR UPDATE
            ]);
            return threads.isEmpty() ? null : threads[0];
        }

        public virtual Integer countRunningThreads(String pool) {
            String normalizedPool = String.isBlank(pool) ? ASYNC_POOL : pool.trim();
            if (normalizedPool == ASYNC_POOL) {
                return [
                    SELECT COUNT()
                    FROM Thread__c
                    WHERE Status__c = 'Running'
                        AND (Pool__c = :normalizedPool OR Pool__c = null)
                ];
            }

            return [
                SELECT COUNT()
                FROM Thread__c
                WHERE Status__c = 'Running'
                    AND Pool__c = :normalizedPool
            ];
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

        public virtual Integer countRunningThreads() {
            return [
                SELECT COUNT()
                FROM Thread__c
                WHERE Status__c = 'Running'
            ];
        }

        public virtual Integer countRunningThreadsExcluding(Id excludedThreadId) {
            return [
                SELECT COUNT()
                FROM Thread__c
                WHERE Status__c = 'Running'
                    AND Id != :excludedThreadId
            ];
        }

        public virtual Integer countRunningThreadsExcluding(String pool, Id excludedThreadId) {
            String normalizedPool = String.isBlank(pool) ? ASYNC_POOL : pool.trim();
            if (normalizedPool == ASYNC_POOL) {
                return [
                    SELECT COUNT()
                    FROM Thread__c
                    WHERE Status__c = 'Running'
                        AND Id != :excludedThreadId
                        AND (Pool__c = :normalizedPool OR Pool__c = null)
                ];
            }

            return [
                SELECT COUNT()
                FROM Thread__c
                WHERE Status__c = 'Running'
                    AND Id != :excludedThreadId
                    AND Pool__c = :normalizedPool
            ];
        }

        public virtual Integer countRunningThreadsExcluding(Id userId, String pool, Id excludedThreadId) {
            String normalizedPool = String.isBlank(pool) ? ASYNC_POOL : pool.trim();
            if (normalizedPool == ASYNC_POOL) {
                return [
                    SELECT COUNT()
                    FROM Thread__c
                    WHERE Status__c = 'Running'
                        AND Id != :excludedThreadId
                        AND CreatedById = :userId
                        AND (Pool__c = :normalizedPool OR Pool__c = null)
                ];
            }

            return [
                SELECT COUNT()
                FROM Thread__c
                WHERE Status__c = 'Running'
                    AND Id != :excludedThreadId
                    AND CreatedById = :userId
                    AND Pool__c = :normalizedPool
            ];
        }

        public virtual List<Thread__c> getRecoverableThreads(DateTime staleBefore, Integer batchSize) {
            Integer safeBatchSize = batchSize == null || batchSize < 1 ? 10 : batchSize;
            List<Thread__c> candidates = (List<Thread__c>) Query.records([
                SELECT Id
                FROM Thread__c
                WHERE Status__c != 'Done'
                    AND Heartbeat__c < :staleBefore
                ORDER BY Heartbeat__c ASC
                LIMIT :safeBatchSize
            ]);
            if (candidates.isEmpty()) return new List<Thread__c>();

            List<Id> candidateIds = new List<Id>();
            for (Thread__c candidate : candidates) {
                candidateIds.add(candidate.Id);
            }

            Map<Id, Thread__c> lockedThreadsById = new Map<Id, Thread__c>((List<Thread__c>) Query.records([
                SELECT Id, Pool__c, Status__c, Run_Key__c, Heartbeat__c
                FROM Thread__c
                WHERE Id IN :candidateIds
                    AND Status__c != 'Done'
                    AND Heartbeat__c < :staleBefore
                FOR UPDATE
            ]));
            List<Thread__c> lockedThreads = new List<Thread__c>();
            for (Id candidateId : candidateIds) {
                if (lockedThreadsById.containsKey(candidateId)) {
                    lockedThreads.add(lockedThreadsById.get(candidateId));
                }
            }
            return lockedThreads;
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

    public virtual with sharing class SettingsService {
        @testVisible Thread_Settings__c values;

        public virtual Integer maxThreads() {
            Decimal maxThreads = getSettings().Max_Threads__c;
            return maxThreads == null || maxThreads < 1 ? 1 : maxThreads.intValue();
        }

        public virtual Integer recoveryThresholdMinutes() {
            Decimal threshold = getSettings().Recovery_Threshold_Minutes__c;
            return threshold == null || threshold < 1 ? 10 : threshold.intValue();
        }

        public virtual Integer recoveryBatchSize() {
            Decimal batchSize = getSettings().Recovery_Batch_Size__c;
            return batchSize == null || batchSize < 1 ? 10 : batchSize.intValue();
        }

        public virtual Integer recoveryLimitThresholdPct() {
            Decimal threshold = getSettings().Recovery_Limit_Threshold_Pct__c;
            return threshold == null || threshold < 1 ? 90 : threshold.intValue();
        }

        public virtual Boolean recoveryEnabled() {
            Thread_Settings__c settings = getSettings();
            return !settings.getPopulatedFieldsAsMap().containsKey('Enable_Recovery__c')
                || settings.Enable_Recovery__c == true;
        }

        public virtual Thread_Settings__c getSettings() {
            if (values == null) {
                values = loadSettings();
            }
            return values;
        }

        public virtual void setSettings(Thread_Settings__c values) {
            this.values = values;
        }

        protected virtual Thread_Settings__c loadSettings() {
            Thread_Settings__c settings = Thread_Settings__c.getInstance();
            return settings == null ? new Thread_Settings__c() : settings;
        }
    }
}
