public with sharing class AsyncThread implements Queueable {
    public Id threadId;
    public Integer failures;

    public AsyncThread(Id threadId, Integer failures) {
        this.threadId = threadId;
        this.failures = failures == null ? 0 : failures;
    }

    public void execute(QueueableContext context) {
        System.debug('Async thread id ' + this.threadId);
        Thread.setCurrent(this.threadId);
        Async.jobs.enqueueNextJob(this.failures);
    }
}
