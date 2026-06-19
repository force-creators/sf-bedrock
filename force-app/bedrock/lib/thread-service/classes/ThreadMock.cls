public with sharing class ThreadMock {
    public Service service;
    public QueryService queries;
    public SettingsService settings;

    public ThreadMock() {
        service = new Service();
        queries = new QueryService();
        settings = new SettingsService();
    }

    public ThreadMock canEnqueue() {
        service.canEnqueue = true;
        return this;
    }

    public ThreadMock thread(Id threadId) {
        service.threadId = threadId;
        return this;
    }

    public ThreadMock mockIds() {
        service.mockIds = true;
        return this;
    }

    public ThreadMock runningThreads(Integer count) {
        queries.runningThreadCount = count == null ? 0 : count;
        queries.globalRunningThreadCount = queries.runningThreadCount;
        return this;
    }

    public ThreadMock seedSettings(Thread_Settings__c settings) {
        this.settings.setSettings(settings);
        return this;
    }

    public ThreadMock runningThreadCounts(List<Integer> counts) {
        queries.runningThreadCounts = counts == null ? new List<Integer>() : counts;
        return this;
    }

    public with sharing class Service extends Thread.Service {
        public Boolean canEnqueue = false;
        public Boolean mockIds = false;
        public Integer continueWorkCalls = 0;
        public Integer startCalls = 0;
        public Integer lastFailures = -1;
        public List<Id> startedThreads = new List<Id>();
        public String mockRunKey = 'mock-run-key';

        public override Id create() {
            return create(Thread.ASYNC_POOL, null);
        }

        public override Id create(String pool, String threadKey) {
            if (!mockIds) {
                return super.create(pool, threadKey);
            }

            Thread__c thread = (Thread__c) new TestData(Thread__c.sObjectType)
                .mockIds()
                .build()[0];
            return thread.Id;
        }

        public override void continueWork(Id threadId, Integer failures) {
            continueWorkCalls++;
            lastFailures = failures;
            ThreadRunner.service.dispatch(threadId, failures);
        }

        public override void start(Id threadId, Integer failures) {
            startCalls++;
            lastFailures = failures;
            startedThreads.add(threadId);

            AsyncOptions options = new AsyncOptions();
            options.maximumQueueableStackDepth = 5;
            System.enqueueJob(new ThreadRunner(threadId, failures), options);
        }

        public override String currentRunKey(Id threadId) {
            return mockIds ? mockRunKey : super.currentRunKey(threadId);
        }

        public override Boolean isRunAuthorized(Id threadId, String runKey) {
            return mockIds ? runKey == mockRunKey : super.isRunAuthorized(threadId, runKey);
        }

        public override Boolean canEnqueue() {
            return canEnqueue;
        }
    }

    public with sharing class QueryService extends Thread.QueryService {
        public List<Thread__c> pendingThreads = new List<Thread__c>();
        public Map<String, List<Thread__c>> pendingThreadsByPool = new Map<String, List<Thread__c>>();
        public Integer runningThreadCount = 0;
        public Integer globalRunningThreadCount = 0;
        public List<Integer> runningThreadCounts = new List<Integer>();
        public List<Thread__c> recoverableThreads = new List<Thread__c>();
        public List<Thread__c> pausedThreads = new List<Thread__c>();

        public override Thread__c getNextPendingThread() {
            return pendingThreads.isEmpty() ? super.getNextPendingThread() : pendingThreads.remove(0);
        }

        public override Thread__c getNextPendingThread(String pool) {
            String normalizedPool = String.isBlank(pool) ? Thread.ASYNC_POOL : pool.trim();
            if (pendingThreadsByPool.containsKey(normalizedPool)
                && !pendingThreadsByPool.get(normalizedPool).isEmpty()) {
                return pendingThreadsByPool.get(normalizedPool).remove(0);
            }
            return pendingThreads.isEmpty() ? super.getNextPendingThread(pool) : pendingThreads.remove(0);
        }

        public override Integer countRunningThreads(Id userId) {
            return nextRunningThreadCount();
        }

        public override Integer countRunningThreads(Id userId, String pool) {
            return nextRunningThreadCount();
        }

        public override Integer countRunningThreads(String pool) {
            return nextRunningThreadCount();
        }

        public override Integer countRunningThreads() {
            return globalRunningThreadCount;
        }

        public override Integer countRunningThreadsExcluding(Id excludedThreadId) {
            return globalRunningThreadCount < 1 ? 0 : globalRunningThreadCount - 1;
        }

        public override Integer countRunningThreadsExcluding(Id userId, String pool, Id excludedThreadId) {
            return runningThreadCount < 1 ? 0 : runningThreadCount - 1;
        }

        public override Integer countRunningThreadsExcluding(String pool, Id excludedThreadId) {
            return runningThreadCount < 1 ? 0 : runningThreadCount - 1;
        }

        public override List<Thread__c> getRecoverableThreads(DateTime staleBefore, Integer batchSize) {
            return recoverableThreads;
        }

        public override List<Thread__c> getPausedThreads(Integer batchSize) {
            return pausedThreads;
        }

        Integer nextRunningThreadCount() {
            return runningThreadCounts.isEmpty() ? runningThreadCount : runningThreadCounts.remove(0);
        }
    }

    public with sharing class SettingsService extends Thread.SettingsService {
    }
}
