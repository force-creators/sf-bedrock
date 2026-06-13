public with sharing class AsyncThread implements Queueable {
    public string threadId;
    public Integer failures;

    public AsyncThread(String threadId, Integer failures) {
        this.threadId = threadId;
        this.failures = failures == null ? 0 : failures;
    }

    public void execute(QueueableContext context) {
        System.debug('Async thread id ' + this.threadId);
        Async.jobs.threadId = this.threadId; //set the thread context
        Async.jobs.enqueueNextJob(this.failures);
    }
}
