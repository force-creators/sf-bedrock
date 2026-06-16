public with sharing class ThreadMock {
    public Service service;
    public QueryService queries;

    public ThreadMock() {
        service = new Service();
        queries = new QueryService();
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
        return this;
    }

    public with sharing class Service extends Thread.Service {
        public Boolean canEnqueue = false;
        public Boolean mockIds = false;
        public Integer continueWorkCalls = 0;
        public Integer startCalls = 0;
        public Integer lastFailures = -1;
        public List<Id> startedThreads = new List<Id>();

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

        public override Boolean canEnqueue() {
            return canEnqueue;
        }
    }

    public with sharing class QueryService extends Thread.QueryService {
        public List<Thread__c> pendingThreads = new List<Thread__c>();
        public Integer runningThreadCount = 0;

        public override Thread__c getNextPendingThread() {
            return pendingThreads.isEmpty() ? null : pendingThreads.remove(0);
        }

        public override Thread__c getNextPendingThread(String pool) {
            return getNextPendingThread();
        }

        public override Integer countRunningThreads(Id userId) {
            return runningThreadCount;
        }

        public override Integer countRunningThreads(Id userId, String pool) {
            return runningThreadCount;
        }
    }
}
