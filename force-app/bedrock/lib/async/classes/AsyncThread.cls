public with sharing class AsyncThread implements Queueable {
    public string threadId;
    public Integer failureCount;

    public AsyncThread(String threadId, Integer failureCount) {
        this.threadId = threadId;
        this.failureCount = failureCount == null ? 0 : failureCount;
    }

    public void execute(QueueableContext context) {
        System.debug('Async thread id ' + this.threadId);
        Async.jobs.threadId = this.threadId; //set the thread context
        Async.jobs.enqueueNextJob(this.failureCount);
    }
}
