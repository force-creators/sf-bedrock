public with sharing class AsyncTriggerHandler extends TriggerHandler {
    public override void afterInsert(List<SObject> newRecords) {
        Async.jobs.enqueue((List<Async__c>) newRecords);
    }

    public override void afterUpdate(List<SObject> records, Map<Id, SObject> old) {
        List<Async__c> newRecords = (List<Async__c>) records;
        Map<Id, Async__c> oldMap = (Map<Id, Async__c>) old;

        if (AsyncFilters.shouldRetry(newRecords, oldMap)) {
            Async.jobs.enqueue(newRecords);
        }
    }
}
