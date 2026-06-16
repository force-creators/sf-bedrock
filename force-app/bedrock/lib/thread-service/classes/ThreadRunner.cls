public virtual with sharing class ThreadRunner implements Queueable {
    public Id threadId;
    public Integer failures;

    public static Service service = new Service();

    public ThreadRunner(Id threadId, Integer failures) {
        this.threadId = threadId;
        this.failures = failures == null ? 0 : failures;
    }

    @testVisible public static void setMock(Service mock) {
        service = mock;
    }

    @testVisible public static void reset() {
        service = new Service();
    }

    public void execute(QueueableContext context) {
        Thread.setCurrent(this.threadId);
        service.dispatch(this.threadId, this.failures);
    }

    public virtual with sharing class Service {
        @testVisible Map<String, Dispatcher> dispatchers = new Map<String, Dispatcher>();

        public virtual void register(String pool, Dispatcher dispatcher) {
            if (String.isBlank(pool) || dispatcher == null) return;
            this.dispatchers.put(pool, dispatcher);
        }

        public virtual void start(Id threadId, Integer failures) {
            if (threadId == null) return;

            Thread.service.running(threadId);
            System.enqueueJob(new ThreadRunner(threadId, failures));
        }

        public virtual void dispatch(Id threadId, Integer failures) {
            dispatcherFor(threadId).dispatch(threadId, failures);
        }

        public virtual Boolean hasPendingWork(Id threadId) {
            return dispatcherFor(threadId).hasPendingWork(threadId);
        }

        public virtual Integer maxThreads(String pool) {
            return dispatcherForPool(pool).maxThreads();
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
            throw new ThreadRunnerException('No ThreadRunner dispatcher is registered for pool ' + normalizedPool + '.');
        }
    }

    public virtual with sharing class Dispatcher {
        public virtual void dispatch(Id threadId, Integer failures) {
            throw new ThreadRunnerException('ThreadRunner dispatchers must implement dispatch(Id, Integer).');
        }

        public virtual Boolean hasPendingWork(Id threadId) {
            return false;
        }

        public virtual Integer maxThreads() {
            return 1;
        }
    }

    public class ThreadRunnerException extends Exception {}
}
