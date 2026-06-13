@istest
public with sharing class SchedulerTest {
    static Integer successfulExecutions = 0;

    class SchedulerSuccessfulJob extends Scheduler {
        public override void execute() {
            successfulExecutions++;
        }
    }

    class SchedulerFailingJob extends Scheduler {
        public override void execute() {
            throw new Scheduler.SchedulerException('Scheduler job failed.');
        }
    }

    @testSetup
    static void setup() {
        Scheduler.reset();
    }

    @istest static void testBaseExecute_requiresOverride() {
        try {
            new Scheduler().execute();
            Assert.fail('Expected the base Scheduler contract to require an override.');
        } catch (Scheduler.SchedulerException error) {
            Assert.areEqual(
                'Scheduler subclasses must override execute().',
                error.getMessage(),
                'Expected the base scheduler contract to explain the missing override.'
            );
        }
    }

    @istest static void testTick_translatesChangedMetadataAndPersistsHash() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .config(new Scheduler_Config__mdt(
                DeveloperName = 'ArchiveJobs',
                Apex__c = 'SchedulerTest.SchedulerSuccessfulJob',
                Is_Enabled__c = true,
                Frequency__c = Scheduler.HOURS,
                Interval__c = 2
            ))
            .job(job('OldJob', 'OldSchedulerJob', true, null));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, dmlMock.upserts.size(), 'Expected one upsert for translated scheduler jobs.');
        Assert.areEqual(2, dmlMock.upserts[0].size(), 'Expected the translated job and disabled stale job to be upserted together.');
        Assert.areEqual(
            mock.metadata.getHash(mock.metadata.configs),
            mock.settings.schedulerSettings.Metadata_Hash__c,
            'Expected the translated metadata hash to persist after a config change.'
        );
        Assert.isNotNull(
            mock.settings.schedulerSettings.Translated_At__c,
            'Expected translation time to be recorded when metadata is re-evaluated.'
        );
        Scheduler__c archiveJob = findJob(dmlMock.upserts[0], 'ArchiveJobs');
        Assert.areEqual(Scheduler.HOURS, archiveJob.Frequency__c, 'Expected metadata frequency to be translated onto the scheduler row.');
        Assert.areEqual(2, archiveJob.Interval__c.intValue(), 'Expected metadata interval to be translated onto the scheduler row.');
        Assert.areEqual(1, successfulExecutions, 'Expected translated enabled jobs to be enqueued and run after the metadata sync.');
    }

    @istest static void testTick_runsEnabledJobsAndClearsPriorErrorOnSuccess() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedSettings(settings('same-hash'))
            .job(job('ArchiveJobs', 'SchedulerTest.SchedulerSuccessfulJob', true, 'previous failure'));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Scheduler__c updatedJob = (Scheduler__c) dmlMock.updates[0][0];
        Assert.areEqual(1, successfulExecutions, 'Expected one enabled scheduler job to execute during the tick.');
        Assert.isNotNull(updatedJob.Last_Executed_At__c, 'Expected job execution time to be recorded after a successful run.');
        Assert.areEqual(null, updatedJob.Last_Error__c, 'Expected a successful run to clear the previous error message.');
    }

    @istest static void testTick_runsEveryFiveMinuteJobEvenWhenRecentlyExecuted() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedSettings(settings('same-hash'))
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.EVERY_FIVE_MINUTES,
                1,
                System.now()
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, successfulExecutions, 'Expected every-five-minute jobs to run on each scheduler tick.');
        Assert.areEqual(1, dmlMock.updates.size(), 'Expected a recent every-five-minute job to still record execution.');
    }

    @istest static void testTick_skipsHourlyJobBeforeInterval() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedSettings(settings('same-hash'))
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.HOURS,
                2,
                System.now().addHours(-1)
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(0, successfulExecutions, 'Expected hourly jobs to wait until their interval has elapsed.');
        Assert.areEqual(0, dmlMock.updates.size(), 'Expected skipped jobs not to record a new execution.');
    }

    @istest static void testTick_runsHourlyJobAfterInterval() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedSettings(settings('same-hash'))
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.HOURS,
                2,
                System.now().addHours(-2)
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, successfulExecutions, 'Expected overdue hourly jobs to run on the next scheduler tick.');
        Assert.areEqual(1, dmlMock.updates.size(), 'Expected overdue hourly jobs to record execution.');
    }

    @istest static void testTick_runsDailyJobAfterInterval() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedSettings(settings('same-hash'))
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.DAYS,
                2,
                System.now().addDays(-2)
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, successfulExecutions, 'Expected overdue daily jobs to run on the next scheduler tick.');
        Assert.areEqual(1, dmlMock.updates.size(), 'Expected overdue daily jobs to record execution.');
    }

    @istest static void testTick_recordsErrorMessageWhenJobFails() {
        SchedulerMock mock = new SchedulerMock()
            .seedSettings(settings('same-hash'))
            .job(job('ResumeJobs', 'SchedulerTest.SchedulerFailingJob', true, null));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Scheduler__c updatedJob = (Scheduler__c) dmlMock.updates[0][0];
        Assert.isNotNull(updatedJob.Last_Executed_At__c, 'Expected failed job attempts to still record an execution timestamp.');
        Assert.areEqual('Scheduler job failed.', updatedJob.Last_Error__c, 'Expected the scheduler to persist the thrown error message.');
    }

    @istest static void testSchedule_usesQuarterHourCronJobs() {
        Test.startTest();
        Scheduler.schedule();
        Test.stopTest();

        List<CronTrigger> cronTriggers = [
            SELECT CronExpression, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Bedrock Scheduler %'
        ];

        Set<String> cronExpressions = new Set<String>();
        for (CronTrigger cronTrigger : cronTriggers) {
            cronExpressions.add(cronTrigger.CronExpression);
        }

        Assert.areEqual(4, cronTriggers.size(), 'Expected scheduler setup to create four quarter-hour scheduler jobs.');
        Assert.isTrue(
            cronExpressions.contains('0 0 * * * ? *'),
            'Expected scheduler setup to create the top-of-hour scheduler job.'
        );
        Assert.isTrue(
            cronExpressions.contains('0 15 * * * ? *'),
            'Expected scheduler setup to create the fifteen-minute scheduler job.'
        );
        Assert.isTrue(
            cronExpressions.contains('0 30 * * * ? *'),
            'Expected scheduler setup to create the thirty-minute scheduler job.'
        );
        Assert.isTrue(
            cronExpressions.contains('0 45 * * * ? *'),
            'Expected scheduler setup to create the forty-five-minute scheduler job.'
        );
    }

    static Id schedulerId() {
        return new TestData.IdService().get(Scheduler__c.SObjectType);
    }

    static Scheduler_Settings__c settings(String hash) {
        return new Scheduler_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Metadata_Hash__c = hash
        );
    }

    static Scheduler__c job(String key, String apex, Boolean isEnabled, String lastError) {
        return job(key, apex, isEnabled, lastError, Scheduler.EVERY_FIVE_MINUTES, 1, null);
    }

    static Scheduler__c job(
        String key,
        String apex,
        Boolean isEnabled,
        String lastError,
        String frequency,
        Integer interval,
        DateTime lastExecutedAt
    ) {
        return new Scheduler__c(
            Id = schedulerId(),
            Config_Key__c = key,
            Apex__c = apex,
            Is_Enabled__c = isEnabled,
            Frequency__c = frequency,
            Interval__c = interval,
            Last_Executed_At__c = lastExecutedAt,
            Last_Error__c = lastError
        );
    }

    static Scheduler__c findJob(List<SObject> rows, String key) {
        for (SObject row : rows) {
            Scheduler__c job = (Scheduler__c) row;
            if (job.Config_Key__c == key) return job;
        }

        Assert.fail('Expected to find scheduler job ' + key + '.');
        return null;
    }
}
