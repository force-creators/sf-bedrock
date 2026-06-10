public with sharing class AsyncMock {
    
    public WorkService work;
    public JobService jobs;
    public QueryService queries;

    public AsyncMock() {
        this.work = new WorkService();
        this.jobs = new JobService();
        this.queries = new QueryService();
    }

    public AsyncMock canEnqueue() {
        this.jobs.canEnqueue = true;
        return this;
    }


    public with sharing class WorkService extends Async.WorkService{

    }

    public with sharing class JobService extends Async.JobService {
        public Boolean canEnqueue = false;

        public override Boolean canEnqueue() {
            return canEnqueue;
        }

        public override void startThread() {
            AsyncOptions options = new AsyncOptions();
            options.maximumQueueableStackDepth = 5;
            System.enqueueJob(new AsyncThread(this.threadId), options);
        }

    }

    public with sharing class QueryService extends Async.QueryService {
    }
}