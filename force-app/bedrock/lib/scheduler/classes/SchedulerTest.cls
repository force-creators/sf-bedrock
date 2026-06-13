@istest
public with sharing class SchedulerTest {
    static Integer successfulExecutions = 0;

    public class SchedulerSuccessfulJob extends Scheduler {
        public override void execute() {
            successfulExecutions++;
        }
    }

    public class SchedulerFailingJob extends Scheduler {
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

    @istest static void testTick_translatesChangedMetadataAndPersistsHashOnRuntimeRows() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .config(new Scheduler_Config__mdt(
                DeveloperName = 'ArchiveJobs',
                Apex__c = 'SchedulerTest.SchedulerSuccessfulJob',
                Is_Enabled__c = true,
                Frequency__c = Scheduler.HOURS,
                Frequency_Value__c = '2'
            ))
            .job(job('ArchiveJobs', 'OldSchedulerJob', false, null))
            .job(job('OldJob', 'OldSchedulerJob', true, null));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, dmlMock.upserts.size(), 'Expected one upsert for translated scheduler jobs.');
        Assert.areEqual(2, dmlMock.upserts[0].size(), 'Expected the translated job and disabled stale job to be upserted together.');
        String expectedHash = mock.metadata.getHash(mock.metadata.configs);
        Scheduler__c archiveJob = findJob(dmlMock.upserts[0], 'ArchiveJobs');
        Scheduler__c staleJob = findJob(dmlMock.upserts[0], 'OldJob');
        Assert.areEqual(Scheduler.HOURS, archiveJob.Frequency__c, 'Expected metadata frequency unit to be translated onto the scheduler row.');
        Assert.areEqual('2', archiveJob.Frequency_Value__c, 'Expected metadata frequency value to be translated onto the scheduler row.');
        Assert.areEqual(expectedHash, archiveJob.Metadata_Hash__c, 'Expected translated jobs to store the metadata hash on the runtime row.');
        Assert.areEqual(expectedHash, staleJob.Metadata_Hash__c, 'Expected disabled stale jobs to store the metadata hash after translation.');
        Assert.areEqual(false, staleJob.Is_Enabled__c, 'Expected scheduler rows with no matching metadata config to be disabled.');
        Assert.areEqual(1, successfulExecutions, 'Expected translated enabled jobs to be enqueued and run after the metadata sync.');
    }

    @istest static void testTick_skipsTranslationWhenRuntimeRowsMatchMetadataHash() {
        successfulExecutions = 0;
        Scheduler_Config__mdt config = new Scheduler_Config__mdt(
            DeveloperName = 'ArchiveJobs',
            Apex__c = 'SchedulerTest.SchedulerSuccessfulJob',
            Is_Enabled__c = true,
            Frequency__c = Scheduler.MINUTES,
            Frequency_Value__c = '5'
        );
        SchedulerMock mock = new SchedulerMock()
            .config(config)
            .seedCurrentHash()
            .job(job('ArchiveJobs', 'SchedulerTest.SchedulerSuccessfulJob', true, null));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(0, dmlMock.upserts.size(), 'Expected scheduler translation to be skipped when runtime rows already carry the current metadata hash.');
        Assert.areEqual(1, successfulExecutions, 'Expected matching runtime rows to still run normally when they are due.');
    }

    @istest static void testTick_runsEnabledJobsAndClearsPriorErrorOnSuccess() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedCurrentHash()
            .job(job('ArchiveJobs', 'SchedulerTest.SchedulerSuccessfulJob', true, 'previous failure'));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, successfulExecutions, 'Expected one enabled scheduler job to execute during the tick.');
        Assert.areEqual(2, dmlMock.updates.size(), 'Expected due jobs to record the heartbeat attempt and the queueable result separately.');
        Scheduler__c attemptedJob = (Scheduler__c) dmlMock.updates[0][0];
        Scheduler__c completedJob = (Scheduler__c) dmlMock.updates[1][0];
        Assert.isNotNull(attemptedJob.Last_Executed_At__c, 'Expected the heartbeat to record the scheduler attempt time before enqueueing.');
        Assert.areEqual(null, completedJob.Last_Executed_At__c, 'Expected queueable completion not to move the scheduler attempt timestamp.');
        Assert.areEqual(null, completedJob.Last_Error__c, 'Expected a successful run to clear the previous error message.');
    }

    @istest static void testTick_runsMinuteJobAfterInterval() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedCurrentHash()
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.MINUTES,
                '5',
                System.now().addMinutes(-5)
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, successfulExecutions, 'Expected minute-based jobs to run once their interval has elapsed.');
        Assert.areEqual(2, dmlMock.updates.size(), 'Expected due minute-based jobs to record the heartbeat attempt and queueable result.');
    }

    @istest static void testTick_skipsMinuteJobBeforeInterval() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedCurrentHash()
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.MINUTES,
                '10',
                System.now().addMinutes(-5)
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(0, successfulExecutions, 'Expected minute-based jobs to wait until their interval has elapsed.');
        Assert.areEqual(0, dmlMock.updates.size(), 'Expected skipped minute-based jobs not to record a new execution.');
    }

    @istest static void testTick_skipsHourlyJobBeforeInterval() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedCurrentHash()
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.HOURS,
                '2',
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
            .seedCurrentHash()
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.HOURS,
                '2',
                System.now().addHours(-2)
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, successfulExecutions, 'Expected overdue hourly jobs to run on the next scheduler tick.');
        Assert.areEqual(2, dmlMock.updates.size(), 'Expected overdue hourly jobs to record the heartbeat attempt and queueable result.');
    }

    @istest static void testTick_runsDailyJobAfterInterval() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedCurrentHash()
            .job(job(
                'ArchiveJobs',
                'SchedulerTest.SchedulerSuccessfulJob',
                true,
                null,
                Scheduler.DAYS,
                '2',
                System.now().addDays(-2)
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(1, successfulExecutions, 'Expected overdue daily jobs to run on the next scheduler tick.');
        Assert.areEqual(2, dmlMock.updates.size(), 'Expected overdue daily jobs to record the heartbeat attempt and queueable result.');
    }

    @istest static void testTick_recordsErrorMessageWhenJobFails() {
        SchedulerMock mock = new SchedulerMock()
            .seedCurrentHash()
            .job(job('ResumeJobs', 'SchedulerTest.SchedulerFailingJob', true, null));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(2, dmlMock.updates.size(), 'Expected failed jobs to record the heartbeat attempt and the queueable error separately.');
        Scheduler__c attemptedJob = (Scheduler__c) dmlMock.updates[0][0];
        Scheduler__c failedJob = (Scheduler__c) dmlMock.updates[1][0];
        Assert.isNotNull(attemptedJob.Last_Executed_At__c, 'Expected failed job attempts to still record the scheduler attempt timestamp.');
        Assert.areEqual(null, failedJob.Last_Executed_At__c, 'Expected queueable failure recording not to move the scheduler attempt timestamp.');
        Assert.areEqual('Scheduler job failed.', failedJob.Last_Error__c, 'Expected the scheduler to persist the thrown error message.');
    }

    @istest static void testJobFinalizer_skipsSuccessfulQueueableResult() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        new Scheduler.JobFinalizer(schedulerId()).recordResult(ParentJobResult.SUCCESS, null);

        Assert.areEqual(0, dmlMock.updates.size(), 'Expected successful queueable results to be recorded by the normal execution path only.');
    }

    @istest static void testJobFinalizer_recordsUnhandledQueueableFailure() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Id schedulerJobId = schedulerId();

        new Scheduler.JobFinalizer(schedulerJobId)
            .recordResult(null, new Scheduler.SchedulerException('Too many SOQL queries: 101'));

        Assert.areEqual(1, dmlMock.updates.size(), 'Expected finalizer failures to update the scheduler runtime row.');
        Scheduler__c updatedJob = (Scheduler__c) dmlMock.updates[0][0];
        Assert.areEqual(schedulerJobId, updatedJob.Id, 'Expected the finalizer to update the scheduler row for the failed queueable.');
        Assert.areEqual(null, updatedJob.Last_Executed_At__c, 'Expected finalizer failures not to move the scheduler attempt timestamp.');
        Assert.areEqual('Too many SOQL queries: 101', updatedJob.Last_Error__c, 'Expected finalizer failures to persist the unhandled queueable error message.');
    }

    @istest static void testTick_recordsRunErrorAndContinuesToNextJob() {
        successfulExecutions = 0;
        Scheduler__c badJob = job('BadJob', 'MissingSchedulerJob', true, null);
        Scheduler__c goodJob = job('GoodJob', 'SchedulerTest.SchedulerSuccessfulJob', true, null);
        SchedulerMock mock = new SchedulerMock()
            .seedCurrentHash()
            .job(badJob)
            .job(goodJob);

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Assert.areEqual(4, dmlMock.updates.size(), 'Expected each due job to record one heartbeat attempt and one result update.');
        Scheduler__c failedAttempt = (Scheduler__c) dmlMock.updates[0][0];
        Scheduler__c failedResult = (Scheduler__c) dmlMock.updates[1][0];
        Scheduler__c successfulAttempt = (Scheduler__c) dmlMock.updates[2][0];
        Scheduler__c successfulResult = (Scheduler__c) dmlMock.updates[3][0];
        Assert.areEqual(1, successfulExecutions, 'Expected a later due job to run after a previous scheduler row fails to enqueue.');
        Assert.areEqual(badJob.Id, failedAttempt.Id, 'Expected the failed scheduler row attempt to be recorded first.');
        Assert.areEqual(badJob.Id, failedResult.Id, 'Expected the failed scheduler row result to be recorded after its attempt.');
        Assert.isNotNull(failedResult.Last_Error__c, 'Expected scheduler run errors to be recorded on the failed row.');
        Assert.areEqual(goodJob.Id, successfulAttempt.Id, 'Expected the later successful scheduler row attempt to be recorded normally.');
        Assert.areEqual(goodJob.Id, successfulResult.Id, 'Expected the later successful scheduler row result to be recorded normally.');
        Assert.areEqual(null, successfulResult.Last_Error__c, 'Expected the later successful scheduler row to clear any previous error.');
    }

    @istest static void testSchedule_usesFiveMinuteCronJobs() {
        Test.startTest();
        Scheduler.schedule();
        Test.stopTest();

        List<CronTrigger> cronTriggers = [
            SELECT CronExpression, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Bedrock Scheduler %'
            AND State != 'DELETED'
        ];

        Set<String> cronExpressions = new Set<String>();
        for (CronTrigger cronTrigger : cronTriggers) {
            cronExpressions.add(cronTrigger.CronExpression);
        }

        Set<String> expectedCronExpressions = new Set<String>();
        for (Integer minute = 0; minute < 60; minute += 5) {
            expectedCronExpressions.add('0 ' + String.valueOf(minute) + ' * * * ? *');
        }

        Assert.areEqual(12, cronTriggers.size(), 'Expected scheduler setup to create twelve five-minute scheduler jobs.');
        Assert.areEqual(
            expectedCronExpressions,
            cronExpressions,
            'Expected scheduler setup to create one scheduler job for each five-minute mark in the hour.'
        );
    }

    @istest static void testSchedulerTick_delegatesToScheduler() {
        successfulExecutions = 0;
        SchedulerMock mock = new SchedulerMock()
            .seedCurrentHash()
            .job(job('ArchiveJobs', 'SchedulerTest.SchedulerSuccessfulJob', true, null));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        new SchedulerTick().execute(null);
        Test.stopTest();

        Assert.areEqual(1, successfulExecutions, 'Expected the top-level schedulable entrypoint to run Scheduler.tick().');
        Assert.areEqual(2, dmlMock.updates.size(), 'Expected jobs run through SchedulerTick to record the heartbeat attempt and queueable result.');
    }

    static Id schedulerId() {
        return new TestData.IdService().get(Scheduler__c.SObjectType);
    }

    static Scheduler__c job(String key, String apex, Boolean isEnabled, String lastError) {
        return job(key, apex, isEnabled, lastError, Scheduler.MINUTES, '5', null);
    }

    static Scheduler__c job(
        String key,
        String apex,
        Boolean isEnabled,
        String lastError,
        String frequency,
        String interval,
        DateTime lastExecutedAt
    ) {
        return new Scheduler__c(
            Id = schedulerId(),
            Config_Key__c = key,
            Apex__c = apex,
            Is_Enabled__c = isEnabled,
            Frequency__c = frequency,
            Frequency_Value__c = interval,
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
