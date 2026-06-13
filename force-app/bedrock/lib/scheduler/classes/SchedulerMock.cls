public with sharing class SchedulerMock {
    public Scheduler.JobService jobs;
    public MetadataService metadata;
    public QueryService queries;
    public SettingsService settings;

    public SchedulerMock() {
        jobs = new Scheduler.JobService();
        metadata = new MetadataService();
        queries = new QueryService();
        settings = new SettingsService();
    }

    public SchedulerMock config(Scheduler_Config__mdt config) {
        metadata.configs.add(config);
        return this;
    }

    public SchedulerMock job(Scheduler__c job) {
        queries.jobs.add(job);
        return this;
    }

    public SchedulerMock seedSettings(Scheduler_Settings__c settingsRecord) {
        settings.schedulerSettings = settingsRecord;
        return this;
    }

    public with sharing class MetadataService extends Scheduler.MetadataService {
        public List<Scheduler_Config__mdt> configs = new List<Scheduler_Config__mdt>();

        public override List<Scheduler_Config__mdt> getConfigs() {
            return configs;
        }
    }

    public with sharing class QueryService extends Scheduler.QueryService {
        public List<Scheduler__c> jobs = new List<Scheduler__c>();

        public override List<Scheduler__c> getJobsByKeys(Set<String> keys) {
            List<Scheduler__c> rows = new List<Scheduler__c>();
            for (Scheduler__c job : jobs) {
                if (keys.contains(job.Config_Key__c)) {
                    rows.add(job);
                }
            }
            return rows;
        }

        public override List<Scheduler__c> getJobsNotInKeys(Set<String> keys) {
            List<Scheduler__c> rows = new List<Scheduler__c>();
            for (Scheduler__c job : jobs) {
                if (keys == null || !keys.contains(job.Config_Key__c)) {
                    rows.add(job);
                }
            }
            return rows;
        }

        public override List<Scheduler__c> getEnabledJobs() {
            List<Scheduler__c> rows = new List<Scheduler__c>();
            for (Scheduler__c job : jobs) {
                if (job.Is_Enabled__c) {
                    rows.add(job);
                }
            }
            return rows;
        }
    }

    public with sharing class SettingsService extends Scheduler.SettingsService {
        public Scheduler_Settings__c schedulerSettings = new Scheduler_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );

        public override Scheduler_Settings__c getSettings() {
            return schedulerSettings;
        }

        public override void saveHash(String hash) {
            schedulerSettings.Metadata_Hash__c = hash;
            schedulerSettings.Translated_At__c = System.now();
        }
    }
}
