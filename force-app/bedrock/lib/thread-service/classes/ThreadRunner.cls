public virtual with sharing class ThreadRunner implements Queueable {
    public Id threadId;
    public Integer failures;
    public String runKey;

    public static Service service = new Service();

    public ThreadRunner(Id threadId, Integer failures) {
        this(threadId, failures, null);
    }

    public ThreadRunner(Id threadId, Integer failures, String runKey) {
        this.threadId = threadId;
        this.failures = failures == null ? 0 : failures;
        this.runKey = String.isBlank(runKey) ? Thread.service.currentRunKey(threadId) : runKey;
    }

    @testVisible public static void setMock(Service mock) {
        service = mock;
    }

    @testVisible public static void reset() {
        service = new Service();
    }

    public void execute(QueueableContext context) {
        Thread.setCurrent(this.threadId);
        if (!service.isRunAuthorized(this.threadId, this.runKey)) return;

        Thread.service.heartbeat(this.threadId);
        service.dispatch(this.threadId, this.failures, this.runKey);
    }

    public virtual with sharing class Service {
        @testVisible Map<String, Dispatcher> dispatchers = new Map<String, Dispatcher>();

        public virtual void register(String pool, Dispatcher dispatcher) {
            if (String.isBlank(pool) || dispatcher == null) return;
            this.dispatchers.put(pool, dispatcher);
        }

        public virtual void start(Id threadId, Integer failures) {
            if (threadId == null) return;

            start(threadId, failures, Thread.service.startRun(threadId));
        }

        public virtual void start(Id threadId, Integer failures, String runKey) {
            if (threadId == null || String.isBlank(runKey)) return;

            System.enqueueJob(new ThreadRunner(threadId, failures, runKey));
        }

        public virtual void dispatch(Id threadId, Integer failures) {
            dispatch(threadId, failures, Thread.service.currentRunKey(threadId));
        }

        public virtual void dispatch(Id threadId, Integer failures, String runKey) {
            dispatcherFor(threadId).dispatch(threadId, failures, runKey);
        }

        public virtual Boolean hasPendingWork(Id threadId) {
            return dispatcherFor(threadId).hasPendingWork(threadId);
        }

        public virtual Integer maxThreads(String pool) {
            return Thread.settings.maxThreads();
        }

        public virtual Boolean isRunAuthorized(Id threadId, String runKey) {
            return Thread.service.isRunAuthorized(threadId, runKey);
        }

        public virtual Dispatcher dispatcherFor(Id threadId) {
            Thread__c threadRecord = Thread.queries.getThread(threadId);
            String pool = threadRecord == null || String.isBlank(threadRecord.Pool__c) ? Thread.ASYNC_POOL : threadRecord.Pool__c;
            return dispatcherForPool(pool);
        }

        public virtual Dispatcher dispatcherForPool(String pool) {
            String normalizedPool = String.isBlank(pool) ? Thread.ASYNC_POOL : pool;
            if (this.dispatchers.containsKey(normalizedPool)) {
                return this.dispatchers.get(normalizedPool);
            }
            if (normalizedPool == Thread.ASYNC_POOL) {
                return new Async.ThreadDispatcher();
            }
            if (normalizedPool == EventRelay.PUBLISH_POOL) {
                return new EventRelay.ThreadDispatcher();
            }
            throw new ThreadRunnerException('No ThreadRunner dispatcher is registered for pool ' + normalizedPool + '.');
        }
    }

    public virtual with sharing class Dispatcher {
        public virtual void dispatch(Id threadId, Integer failures) {
            throw new ThreadRunnerException('ThreadRunner dispatchers must implement dispatch(Id, Integer).');
        }

        public virtual void dispatch(Id threadId, Integer failures, String runKey) {
            dispatch(threadId, failures);
        }

        public virtual Boolean hasPendingWork(Id threadId) {
            return false;
        }

        public virtual Boolean hasRecoverableWork(Id threadId) {
            return hasPendingWork(threadId);
        }

        public virtual void prepareRecovery(Id threadId) {
        }

        public virtual Integer maxThreads() {
            return 1;
        }
    }

    public class ThreadRunnerException extends Exception {}
}
