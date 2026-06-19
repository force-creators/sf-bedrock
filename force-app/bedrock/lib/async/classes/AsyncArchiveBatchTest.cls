@istest(testFor='ApexClass:AsyncArchiveBatch')
public with sharing class AsyncArchiveBatchTest {
    @istest static void testArchiveBatch_movesDoneWorkPastThresholdAndDeletesDrainedThreads() {
        Thread__c archivedThread = new Thread__c(Status__c = Thread.consts.DONE);
        Thread__c retainedThread = new Thread__c(Status__c = Thread.consts.DONE);
        insert new List<Thread__c> { archivedThread, retainedThread };
        archivedThread = [SELECT Id, Name FROM Thread__c WHERE Id = :archivedThread.Id];
        retainedThread = [SELECT Id, Name FROM Thread__c WHERE Id = :retainedThread.Id];

        Async__c oldDone = workItem('ArchivedJob', UserInfo.getUserId(), 'Done', archivedThread.Id);
        oldDone.Priority__c = 9;
        oldDone.Retry_Count__c = 2;
        Async__c recentDone = workItem('RecentJob', UserInfo.getUserId(), 'Done', retainedThread.Id);
        Async__c remainingWork = workItem('RetainedJob', UserInfo.getUserId(), 'Pending', retainedThread.Id);
        DML.insertRecords(new List<SObject> { oldDone, recentDone, remainingWork });
        Test.setCreatedDate(oldDone.Id, System.now().addHours(-3));
        Test.setCreatedDate(recentDone.Id, System.now());

        Async.settings.setSettings(new Async_Settings__c(Archive_Threshold_Hours__c = 1));

        Test.startTest();
            Database.executeBatch(new AsyncArchiveBatch(), 200);
        Test.stopTest();

        List<Async_Archive__c> archives = [
            SELECT Apex__c, Priority__c, Record_Id__c, Retry_Count__c, Status__c, Thread__c
            FROM Async_Archive__c
        ];
        Assert.areEqual(1, archives.size(), 'Expected the archive batch to move only Done work older than the threshold.');
        Assert.areEqual('ArchivedJob', archives[0].Apex__c, 'Expected the archived record to copy the source Apex class.');
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), archives[0].Record_Id__c, 'Expected the archived record to copy the source record id.');
        Assert.areEqual(9, archives[0].Priority__c, 'Expected the archived record to copy the source priority.');
        Assert.areEqual(2, archives[0].Retry_Count__c, 'Expected the archived record to copy the source retry count.');
        Assert.areEqual('Done', archives[0].Status__c, 'Expected the archived record to copy the source status.');
        Assert.areEqual(archivedThread.Name, archives[0].Thread__c, 'Expected the archived record to store the thread number as text.');

        Assert.areEqual(2, [SELECT COUNT() FROM Async__c], 'Expected archived Async__c work to be deleted after copying.');
        Assert.areEqual(0, [SELECT COUNT() FROM Thread__c WHERE Id = :archivedThread.Id], 'Expected the drained source thread to be deleted.');
        Assert.areEqual(1, [SELECT COUNT() FROM Thread__c WHERE Id = :retainedThread.Id], 'Expected a thread with remaining async work to be retained.');
    }

    @istest static void testArchiveBatch_allowsZeroThresholdForImmediateArchive() {
        Thread__c thread = new Thread__c(Status__c = Thread.consts.DONE);
        insert thread;

        Async__c workItem = workItem('ImmediateArchiveJob', UserInfo.getUserId(), 'Done', thread.Id);
        DML.insertRecords(new List<SObject> { workItem });

        Async.settings.setSettings(new Async_Settings__c(Archive_Threshold_Hours__c = 0));

        Test.startTest();
            Database.executeBatch(new AsyncArchiveBatch(), 200);
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Async_Archive__c WHERE Apex__c = 'ImmediateArchiveJob'],
            'Expected zero Archive Threshold Hours to archive completed work without waiting.');
        Assert.areEqual(0, [SELECT COUNT() FROM Async__c WHERE Id = :workItem.Id],
            'Expected the immediately archived work item to be deleted from Async__c.');
    }

    @istest static void testArchiveBatch_chainsCleanupWhenEnabled() {
        Async_Archive__c oldArchive = new Async_Archive__c(
            Apex__c = 'OldArchive',
            Record_Id__c = String.valueOf(UserInfo.getUserId()),
            Status__c = 'Done',
            Thread__c = 'T-0001'
        );
        insert oldArchive;
        Test.setCreatedDate(oldArchive.Id, System.now().addDays(-1));

        Async.settings.setSettings(new Async_Settings__c(
            Archive_Threshold_Hours__c = 24,
            Enable_Archive_Cleanup__c = true,
            Max_Archive_Age__c = 0
        ));

        Test.startTest();
            new AsyncArchiveBatch().finish(null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Async_Archive__c WHERE Id = :oldArchive.Id],
            'Expected archive cleanup to run after archive finish when cleanup is enabled.');
    }

    @istest static void testArchiveCleanupBatch_deletesArchiveRowsPastMaxAge() {
        Async_Archive__c oldArchive = archive('OldArchive', 'T-0001');
        Async_Archive__c recentArchive = archive('RecentArchive', 'T-0002');
        insert new List<Async_Archive__c> { oldArchive, recentArchive };
        Test.setCreatedDate(oldArchive.Id, System.now().addDays(-3));
        Test.setCreatedDate(recentArchive.Id, System.now());

        Async.settings.setSettings(new Async_Settings__c(Max_Archive_Age__c = 1));

        Test.startTest();
            Database.executeBatch(new AsyncArchiveCleanupBatch(), 200);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Async_Archive__c WHERE Id = :oldArchive.Id],
            'Expected cleanup to delete archive rows older than the configured max age.');
        Assert.areEqual(1, [SELECT COUNT() FROM Async_Archive__c WHERE Id = :recentArchive.Id],
            'Expected cleanup to keep archive rows inside the configured max age.');
    }

    static Async__c workItem(String apexClass, Id recordId, String status, Id threadId) {
        Async__c workItem = new Async__c(
            Apex__c = apexClass,
            Record_Id__c = String.valueOf(recordId),
            Status__c = status
        );
        workItem.put('Thread__c', threadId);
        return workItem;
    }

    static Async_Archive__c archive(String apexClass, String thread) {
        return new Async_Archive__c(
            Apex__c = apexClass,
            Record_Id__c = String.valueOf(UserInfo.getUserId()),
            Status__c = 'Done',
            Thread__c = thread
        );
    }
}
