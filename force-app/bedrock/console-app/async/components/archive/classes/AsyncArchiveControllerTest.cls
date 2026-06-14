@istest(testFor='ApexClass:AsyncArchiveController')
public with sharing class AsyncArchiveControllerTest {
    @istest static void testGetArchives_returnsFilteredAndSortedArchiveRows() {
        DML.insertRecords(new List<SObject> {
            archive('ZebraArchive', '001000000000001AAA', 'T-0001'),
            archive('AlphaArchive', '001000000000002AAA', 'T-0002')
        });

        Test.startTest();
        List<AsyncArchiveController.ArchiveRow> filteredRows = AsyncArchiveController.getArchives('Alpha', 'apexClass', 'asc');
        List<AsyncArchiveController.ArchiveRow> sortedRows = AsyncArchiveController.getArchives(null, 'apexClass', 'asc');
        Test.stopTest();

        Assert.areEqual(1, filteredRows.size(), 'Expected the archive tab filter to match Apex, record id, thread, or archive number text.');
        Assert.areEqual('AlphaArchive', filteredRows[0].apexClass, 'Expected the filtered result to keep the matching row.');

        Assert.areEqual('AlphaArchive', sortedRows[0].apexClass, 'Expected sorting to honor the requested ascending class order.');
        Assert.areEqual('ZebraArchive', sortedRows[1].apexClass, 'Expected sorting to include the second row after the first.');
        Assert.isNotNull(sortedRows[0].archiveNumber, 'Expected each archive row to include the archive number.');
        Assert.isNotNull(sortedRows[0].createdDate, 'Expected each archive row to include the archive created date.');
    }

    @istest static void testRunNow_startsArchiveBatch() {
        Test.startTest();
        Id jobId = AsyncArchiveController.runNow();
        Test.stopTest();

        Assert.isNotNull(jobId, 'Expected Run Now to enqueue the archive batch and return a job id.');
    }

    static Async_Archive__c archive(String apexClass, String recordId, String thread) {
        return new Async_Archive__c(
            Apex__c = apexClass,
            Record_Id__c = recordId,
            Status__c = 'Done',
            Thread__c = thread
        );
    }
}
