public with sharing class AsyncArchiveJob extends Scheduler {
    public static Id runNow() {
        return Database.executeBatch(new AsyncArchiveBatch(), 200);
    }

    public override void execute() {
        runNow();
    }
}
