@istest(testFor='ApexClass:ThreadMonitorController')
public with sharing class ThreadMonitorControllerTest {
    @istest static void testGetRunning_returnsNonDoneThreadsWithHealth() {
        Datetime now = System.now();
        Thread.settings.setSettings(new Thread_Settings__c(Recovery_Threshold_Minutes__c = 10));
        DML.insertRecords(new List<SObject> {
            thread(Thread.consts.RUNNING, 'Async', 'request:active', now.addMinutes(-1), null, '0123456789abcdef'),
            thread(Thread.consts.PENDING, 'Async', 'request:stale', now.addMinutes(-20), null, null),
            thread(Thread.consts.DONE, 'Async', 'request:done', now.addMinutes(-30), now, null)
        });

        Test.startTest();
        List<ThreadMonitorController.ThreadRow> rows = ThreadMonitorController.getRunning(null, 'threadKey', 'asc');
        Test.stopTest();

        Assert.areEqual(2, rows.size(), 'Expected the running tab to include pending and running infrastructure threads.');
        Assert.areEqual('request:active', rows[0].threadKey, 'Expected sorting to honor the requested thread key order.');
        Assert.areEqual('Running', rows[0].health, 'Expected a fresh running thread to be labeled healthy.');
        Assert.areEqual('request:stale', rows[1].threadKey, 'Expected the stale pending thread to stay in the running tab.');
        Assert.isTrue(rows[1].isStale, 'Expected a non-done thread past the heartbeat threshold to be marked stale.');
        Assert.areEqual('Stale heartbeat', rows[1].health, 'Expected stale rows to surface the heartbeat problem.');
        Assert.areEqual('01234567...cdef', rows[0].runKey, 'Expected the run key to be represented with a safe diagnostic preview.');
    }

    @istest static void testGetCompleted_appliesSearchAndSort() {
        Datetime now = System.now();
        DML.insertRecords(new List<SObject> {
            thread(Thread.consts.DONE, 'Async', 'request:zebra', now.addMinutes(-30), now.addMinutes(-1), null),
            thread(Thread.consts.DONE, 'Event', 'request:alpha', now.addMinutes(-20), now, null),
            thread(Thread.consts.RUNNING, 'Async', 'request:ignored', now, null, null)
        });

        Test.startTest();
        List<ThreadMonitorController.ThreadRow> filteredRows = ThreadMonitorController.getCompleted('alpha', 'pool', 'asc');
        List<ThreadMonitorController.ThreadRow> sortedRows = ThreadMonitorController.getCompleted(null, 'pool', 'asc');
        Test.stopTest();

        Assert.areEqual(1, filteredRows.size(), 'Expected completed tab search to match thread key, pool, status, number, user, or run key text.');
        Assert.areEqual('Event', filteredRows[0].pool, 'Expected the filtered completed result to keep the matching row.');
        Assert.areEqual('Async', sortedRows[0].pool, 'Expected completed tab sorting to honor the requested ascending pool order.');
        Assert.areEqual('Event', sortedRows[1].pool, 'Expected completed tab sorting to include the second completed row.');
    }

    static Thread__c thread(
        String status,
        String pool,
        String threadKey,
        Datetime heartbeatAt,
        Datetime completedAt,
        String runKey
    ) {
        return new Thread__c(
            Status__c = status,
            Pool__c = pool,
            Thread_Key__c = threadKey,
            Heartbeat__c = heartbeatAt,
            Started__c = status == Thread.consts.RUNNING ? heartbeatAt : null,
            Completed__c = completedAt,
            Run_Key__c = runKey
        );
    }
}
