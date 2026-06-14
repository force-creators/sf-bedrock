@istest(testFor='ApexClass:AsyncDashboardController')
public with sharing class AsyncDashboardControllerTest {
    @istest static void testGetMetrics_countsAsyncJobs() {
        Thread__c firstThread = new Thread__c(Status__c = 'Running');
        Thread__c secondThread = new Thread__c(Status__c = 'Running');
        insert new List<Thread__c> { firstThread, secondThread };

        List<SObject> workItems = new List<SObject>{
            workItem('FirstJob', firstThread.Id, 'Done'),
            workItem('SecondJob', firstThread.Id, 'Pending'),
            workItem('ThirdJob', secondThread.Id, 'Running'),
            workItem('FourthJob', secondThread.Id, 'Error')
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
        Assert.areEqual(
            4,
            metrics.totalJobs,
            'The dashboard should count every async job regardless of status.'
        );
    }

    static Async__c workItem(String apexClass, Id threadId, String status) {
        Async__c workItem = new Async__c(Apex__c = apexClass, Status__c = status);
        workItem.put('Thread__c', threadId);
        return workItem;
    }
}
