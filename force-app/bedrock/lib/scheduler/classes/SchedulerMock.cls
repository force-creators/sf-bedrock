public with sharing class SchedulerMock {
    public Scheduler.JobService jobs;
    public MetadataService metadata;
    public QueryService queries;
    public SettingsService settings;

    public SchedulerMock() {
        this.jobs = new Scheduler.JobService();
        this.metadata = new MetadataService();
        this.queries = new QueryService();
        this.settings = new SettingsService();
    }

    public SchedulerMock config(Scheduler_Config__mdt config) {
        this.metadata.configs.add(config);
        return this;
    }

    public SchedulerMock job(Scheduler__c job) {
        this.queries.jobs.add(job);
        return this;
    }

    public SchedulerMock seedSettings(Scheduler_Settings__c settingsRecord) {
        this.settings.schedulerSettings = settingsRecord;
        return this;
    }

    public with sharing class MetadataService extends Scheduler.MetadataService {
        public List<Scheduler_Config__mdt> configs = new List<Scheduler_Config__mdt>();

        public override List<Scheduler_Config__mdt> getConfigs() {
            return this.configs;
        }
    }

    public with sharing class QueryService extends Scheduler.QueryService {
        public List<Scheduler__c> jobs = new List<Scheduler__c>();

        public override List<Scheduler__c> getJobsByKeys(Set<String> keys) {
            List<Scheduler__c> results = new List<Scheduler__c>();

            for (Scheduler__c job : this.jobs) {
                if (keys.contains(job.Config_Key__c)) {
                    results.add(job);
                }
            }

            return results;
        }

        public override List<Scheduler__c> getJobsNotInKeys(Set<String> keys) {
            List<Scheduler__c> results = new List<Scheduler__c>();

            for (Scheduler__c job : this.jobs) {
                if (keys == null || !keys.contains(job.Config_Key__c)) {
                    results.add(job);
                }
            }

            return results;
        }

        public override List<Scheduler__c> getRunnableJobs() {
            List<Scheduler__c> results = new List<Scheduler__c>();

            for (Scheduler__c job : this.jobs) {
                if (job.Is_Enabled__c) {
                    results.add(job);
                }
            }

            return results;
        }
    }

    public with sharing class SettingsService extends Scheduler.SettingsService {
        public Scheduler_Settings__c schedulerSettings = new Scheduler_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId()
        );

        public override Scheduler_Settings__c getSettings() {
            return this.schedulerSettings;
        }

        public override void saveHash(String hash) {
            this.schedulerSettings.Metadata_Hash__c = hash;
            this.schedulerSettings.Translated_At__c = System.now();
        }
    }
}
