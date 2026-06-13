@istest
public with sharing class SchedulerTest {
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
        TestData.IdService ids = new TestData.IdService();
        SchedulerSuccessfulJob.executions = 0;
        SchedulerMock mock = new SchedulerMock()
            .config(new Scheduler_Config__mdt(
                DeveloperName = 'ArchiveJobs',
                Apex__c = 'SchedulerSuccessfulJob',
                Is_Enabled__c = true
            ))
            .job(new Scheduler__c(
                Id = ids.get(Scheduler__c.SObjectType),
                Config_Key__c = 'OldJob',
                Apex__c = 'OldSchedulerJob',
                Is_Enabled__c = true
            ));

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
        Assert.areEqual(1, SchedulerSuccessfulJob.executions, 'Expected translated enabled jobs to be enqueued and run after the metadata sync.');
    }

    @istest static void testTick_runsEnabledJobsAndClearsPriorErrorOnSuccess() {
        SchedulerSuccessfulJob.executions = 0;
        TestData.IdService ids = new TestData.IdService();

        SchedulerMock mock = new SchedulerMock()
            .seedSettings(new Scheduler_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Metadata_Hash__c = 'same-hash'
            ))
            .job(new Scheduler__c(
                Id = ids.get(Scheduler__c.SObjectType),
                Config_Key__c = 'ArchiveJobs',
                Apex__c = 'SchedulerSuccessfulJob',
                Is_Enabled__c = true,
                Last_Error__c = 'previous failure'
            ));

        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Scheduler.setMock(mock);

        Test.startTest();
        Scheduler.tick();
        Test.stopTest();

        Scheduler__c updatedJob = (Scheduler__c) dmlMock.updates[0][0];
        Assert.areEqual(1, SchedulerSuccessfulJob.executions, 'Expected one enabled scheduler job to execute during the tick.');
        Assert.isNotNull(updatedJob.Last_Executed_At__c, 'Expected job execution time to be recorded after a successful run.');
        Assert.areEqual(null, updatedJob.Last_Error__c, 'Expected a successful run to clear the previous error message.');
    }

    @istest static void testTick_recordsErrorMessageWhenJobFails() {
        TestData.IdService ids = new TestData.IdService();
        SchedulerMock mock = new SchedulerMock()
            .seedSettings(new Scheduler_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Metadata_Hash__c = 'same-hash'
            ))
            .job(new Scheduler__c(
                Id = ids.get(Scheduler__c.SObjectType),
                Config_Key__c = 'ResumeJobs',
                Apex__c = 'SchedulerFailingJob',
                Is_Enabled__c = true
            ));

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
}
