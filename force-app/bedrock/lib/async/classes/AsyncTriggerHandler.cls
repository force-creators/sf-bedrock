public with sharing class AsyncTriggerHandler extends TriggerHandler{
    
    public override void afterInsert(List<SObject> newRecords) {
        Async.jobs.enqueue();
    }
}