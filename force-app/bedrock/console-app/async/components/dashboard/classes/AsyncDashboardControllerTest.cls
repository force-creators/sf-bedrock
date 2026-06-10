@istest(testFor='ApexClass:AsyncDashboardController')
public with sharing class AsyncDashboardControllerTest {
    @istest static void testGetMetrics_countsAsyncJobs() {
        List<SObject> workItems = new List<SObject>{
            new Async__c(Apex__c = 'FirstJob', Thread__c = 'thread-one', Status__c = 'Done'),
            new Async__c(Apex__c = 'SecondJob', Thread__c = 'thread-one', Status__c = 'Pending'),
            new Async__c(Apex__c = 'ThirdJob', Thread__c = 'thread-two', Status__c = 'Running'),
            new Async__c(Apex__c = 'FourthJob', Thread__c = 'thread-two', Status__c = 'Error')
        };
        DML.insertRecords(workItems);

        Test.startTest();
        AsyncDashboardController.DashboardMetrics metrics = AsyncDashboardController.getMetrics();
        Test.stopTest();

        Assert.areEqual(
            1,
            metrics.jobsCompletedToday,
            'The dashboard should count async jobs marked done today.'
        );
        Assert.areEqual(
            2,
            metrics.backlogCount,
            'The dashboard should count pending and running async jobs as backlog.'
        );
        Assert.areEqual(
            1,
            metrics.errors,
            'The dashboard should count async jobs currently in error.'
        );
    }
}
