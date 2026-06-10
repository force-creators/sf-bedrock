public with sharing class AsyncFilters {
    
    public static Boolean shouldRetry(List<Async__c> records, Map<Id, Async__c> oldMap) {
        for (Async__c record : records) {
            if (record.Status__c == 'Pending' && oldMap.get(record.Id).Status__c == 'Error') {
                return true;
            }
        }
        return false;
    }
}