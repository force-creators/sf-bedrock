public with sharing class AsyncFilters {
    public static Boolean shouldRetry(List<Async__c> records, Map<Id, Async__c> oldMap) {
        for (Async__c record : records) {
            if (record.Status__c == Async.consts.PENDING && oldMap.get(record.Id).Status__c == Async.consts.ERROR) {
                return true;
            }
        }
        return false;
    }
}
