public with sharing class ThreadDashboardController {
    @AuraEnabled
    public static DashboardMetrics getMetrics() {
        Datetime staleBefore = System.now().addMinutes(-Thread.settings.recoveryThresholdMinutes());
        DashboardMetrics metrics = new DashboardMetrics();

        metrics.runningThreads = [
            SELECT COUNT()
            FROM Thread__c
            WHERE Status__c = 'Running'
        ];

        metrics.pendingThreads = [
            SELECT COUNT()
            FROM Thread__c
            WHERE Status__c = 'Pending'
        ];

        metrics.staleThreads = [
            SELECT COUNT()
            FROM Thread__c
            WHERE Status__c != 'Done'
                AND Heartbeat__c < :staleBefore
        ];

        metrics.completedToday = [
            SELECT COUNT()
            FROM Thread__c
            WHERE Status__c = 'Done'
                AND Completed__c = TODAY
        ];

        return metrics;
    }

    public class DashboardMetrics {
        @AuraEnabled public Integer runningThreads;
        @AuraEnabled public Integer pendingThreads;
        @AuraEnabled public Integer staleThreads;
        @AuraEnabled public Integer completedToday;
    }
}
