public with sharing class AsyncThread implements Queueable {
    public string threadId;
    public AsyncThread(String threadId) {
        this.threadId = threadId;
    }

    public void execute(QueueableContext context) {
        Async.jobs.threadId = this.threadId; //set the thread context
        Async.jobs.enqueueNextJob();
    }
}