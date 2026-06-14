public with sharing class AsyncArchiveCleanupBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime deleteBefore = System.now().addDays(-Async.settings.maxArchiveAgeDays());
        return Database.getQueryLocator([
            SELECT Id
            FROM Async_Archive__c
            WHERE CreatedDate <= :deleteBefore
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) return;

        DML.deleteRecords(scope);
    }

    public void finish(Database.BatchableContext context) {
    }
}
