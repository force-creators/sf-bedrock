@istest(testFor='ApexClass:SchedulerConsoleController')
public with sharing class SchedulerConsoleControllerTest {
    @istest static void testGetSchedule_calculatesLiveTimeline() {
        Datetime lastRan = System.now().addHours(-2);
        SchedulerMock mock = new SchedulerMock()
            .config(new Scheduler_Config__mdt(
                DeveloperName = 'HourlyJob',
                Apex__c = 'HourlyJob',
                Is_Enabled__c = true,
                Frequency__c = Scheduler.HOURS,
                Frequency_Value__c = '3'
            ))
            .seedCurrentHash()
            .job(new Scheduler__c(
                Config_Key__c = 'HourlyJob',
                Apex__c = 'HourlyJob',
                Is_Enabled__c = true,
                Frequency__c = Scheduler.HOURS,
                Frequency_Value__c = '3',
                Last_Executed_At__c = lastRan
            ))
            .job(new Scheduler__c(
                Config_Key__c = 'DisabledJob',
                Apex__c = 'DisabledJob',
                Is_Enabled__c = false,
                Frequency__c = Scheduler.MINUTES,
                Frequency_Value__c = '2',
                Last_Error__c = 'Previous failure'
            ));
        Scheduler.setMock(mock);

        Test.startTest();
        SchedulerConsoleController.ConsoleState state = SchedulerConsoleController.getSchedule();
        Test.stopTest();

        Scheduler.reset();

        Assert.areEqual(
            2,
            state.jobs.size(),
            'The console should return one row for each scheduler runtime record.'
        );
        Assert.areEqual(
            1,
            state.enabledJobCount,
            'The console should count enabled scheduler jobs.'
        );
        Assert.areEqual(
            1,
            state.disabledJobCount,
            'The console should count disabled scheduler jobs.'
        );
        Assert.areEqual(
            1,
            state.errorJobCount,
            'The console should count scheduler jobs with a stored last error.'
        );

        SchedulerConsoleController.JobRow hourlyRow = findRow(state.jobs, 'HourlyJob');
        Assert.areEqual(
            lastRan.addHours(3),
            hourlyRow.nextScheduledAt,
            'The console should calculate the next run time from the last execution and cadence.'
        );
        Assert.areEqual(
            'Every 3 hours',
            hourlyRow.cadence,
            'The console should render a readable cadence label for hour-based jobs.'
        );
        Assert.areEqual(
            'Scheduled',
            hourlyRow.status,
            'A future enabled job should be shown as scheduled.'
        );

        SchedulerConsoleController.JobRow disabledRow = findRow(state.jobs, 'DisabledJob');
        Assert.areEqual(
            null,
            disabledRow.nextScheduledAt,
            'Disabled jobs should not show a next scheduled run time.'
        );
        Assert.areEqual(
            'Every 5 minutes',
            disabledRow.cadence,
            'Minute-based jobs should use the same five-minute minimum as Scheduler.'
        );
        Assert.areEqual(
            'Disabled',
            disabledRow.status,
            'Disabled jobs should be clearly marked as disabled.'
        );
    }

    @istest static void testGetSchedule_surfacesPendingMetadataRecalculation() {
        SchedulerMock mock = new SchedulerMock()
            .config(new Scheduler_Config__mdt(
                DeveloperName = 'ChangedJob',
                Apex__c = 'ChangedJob',
                Is_Enabled__c = true,
                Frequency__c = Scheduler.MINUTES,
                Frequency_Value__c = '5'
            ))
            .job(new Scheduler__c(
                Config_Key__c = 'ChangedJob',
                Apex__c = 'ChangedJob',
                Is_Enabled__c = true,
                Frequency__c = Scheduler.MINUTES,
                Frequency_Value__c = '5',
                Metadata_Hash__c = 'stale'
            ));
        Scheduler.setMock(mock);

        Test.startTest();
        SchedulerConsoleController.ConsoleState state = SchedulerConsoleController.getSchedule();
        Test.stopTest();

        Scheduler.reset();

        Assert.isTrue(
            state.hasMetadataChanges,
            'The console should detect when runtime scheduler rows no longer match metadata.'
        );
        Assert.isNotNull(
            state.metadataRecalculationAt,
            'The console should report the next heartbeat time when metadata will be recalculated.'
        );
        Assert.isTrue(
            state.metadataRecalculationAt >= state.generatedAt,
            'The recalculation time should not be earlier than the console snapshot time.'
        );
    }

    static SchedulerConsoleController.JobRow findRow(
        List<SchedulerConsoleController.JobRow> rows,
        String configKey
    ) {
        for (SchedulerConsoleController.JobRow row : rows) {
            if (row.configKey == configKey) return row;
        }

        Assert.fail('Expected to find scheduler row for ' + configKey + '.');
        return null;
    }
}
