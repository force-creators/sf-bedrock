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
                Is_Enabled__c = true
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

    @istest static void testSchedule_usesFiveMinuteCron() {
        Test.startTest();
        Id jobId = Scheduler.schedule();
        Test.stopTest();

        CronTrigger cronTrigger = [
            SELECT CronExpression
            FROM CronTrigger
            WHERE Id = :jobId
            LIMIT 1
        ];

        Assert.areEqual('0 0/5 * * * ? *', cronTrigger.CronExpression, 'Expected scheduler setup to use a five-minute cron expression.');
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
        return new Scheduler__c(
            Id = schedulerId(),
            Config_Key__c = key,
            Apex__c = apex,
            Is_Enabled__c = isEnabled,
            Last_Error__c = lastError
        );
    }
}
