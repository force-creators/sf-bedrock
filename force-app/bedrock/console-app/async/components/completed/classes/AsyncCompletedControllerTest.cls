@istest(testFor='ApexClass:AsyncCompletedController')
public with sharing class AsyncCompletedControllerTest {
    @istest static void testGetCompleted_returnsDoneRowsForMvp() {
        DML.insertRecords(new List<SObject>{
            new Async__c(
                Apex__c = 'CompletedJob',
                Record_Id__c = '001000000000001AAA',
                Status__c = 'Done',
                Thread__c = 'thread-a'
            ),
            new Async__c(
                Apex__c = 'IgnoredError',
                Record_Id__c = '001000000000002AAA',
                Status__c = 'Error',
                Thread__c = 'thread-b'
            )
        });

        Test.startTest();
        List<AsyncCompletedController.CompletedRow> rows = AsyncCompletedController.getCompleted(null, null, null);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'Expected the completed tab query to return only Done work items.');
        Assert.isNotNull(rows[0].asyncJobNumber, 'Expected the completed row to include the async job number.');
        Assert.areEqual('CompletedJob', rows[0].apexClass, 'Expected the completed row to include the Apex class.');
        Assert.areEqual('001000000000001AAA', rows[0].recordId, 'Expected the completed row to include the record id.');
        Assert.areEqual('thread-a', rows[0].thread, 'Expected the completed row to include the thread id.');
        Assert.isNotNull(rows[0].createdDate, 'Expected the completed row to include the created date for MVP ordering.');
    }

    @istest static void testGetCompleted_appliesSearchAndSort() {
        DML.insertRecords(new List<SObject>{
            new Async__c(
                Apex__c = 'ZebraJob',
                Record_Id__c = '001000000000003AAA',
                Status__c = 'Done',
                Thread__c = 'alpha-thread'
            ),
            new Async__c(
                Apex__c = 'AlphaJob',
                Record_Id__c = '001000000000004AAA',
                Status__c = 'Done',
                Thread__c = 'beta-thread'
            )
        });

        Test.startTest();
        List<AsyncCompletedController.CompletedRow> filteredRows = AsyncCompletedController.getCompleted('beta', 'apexClass', 'asc');
        List<AsyncCompletedController.CompletedRow> sortedRows = AsyncCompletedController.getCompleted(null, 'apexClass', 'asc');
        Test.stopTest();

        Assert.areEqual(1, filteredRows.size(), 'Expected the completed tab filter to match Apex, record id, thread, or job number text.');
        Assert.areEqual('AlphaJob', filteredRows[0].apexClass, 'Expected the filtered result to keep the matching row.');

        Assert.areEqual('AlphaJob', sortedRows[0].apexClass, 'Expected sorting to honor the requested ascending class order.');
        Assert.areEqual('ZebraJob', sortedRows[1].apexClass, 'Expected sorting to include the second row after the first.');
    }
}
