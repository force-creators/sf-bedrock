public with sharing class AsyncDashboardController {
    @AuraEnabled
    public static DashboardMetrics getMetrics() {
        DashboardMetrics metrics = new DashboardMetrics();

        metrics.jobsCompletedToday = [
            SELECT COUNT()
            FROM Async__c
            WHERE Status__c = 'Done'
                AND LastModifiedDate = TODAY
            WITH USER_MODE
        ];

        metrics.backlogCount = [
            SELECT COUNT()
            FROM Async__c
            WHERE Status__c NOT IN ('Done', 'Error')
            WITH USER_MODE
        ];

        metrics.errors = [
            SELECT COUNT()
            FROM Async__c
            WHERE Status__c = 'Error'
            WITH USER_MODE
        ];

        return metrics;
    }

    public class DashboardMetrics {
        @AuraEnabled public Integer jobsCompletedToday;
        @AuraEnabled public Integer backlogCount;
        @AuraEnabled public Integer errors;
    }
}
