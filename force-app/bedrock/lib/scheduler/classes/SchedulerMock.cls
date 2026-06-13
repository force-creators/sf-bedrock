public with sharing class SchedulerMock {
    public Scheduler.JobService jobs;
    public MetadataService metadata;
    public QueryService queries;
    String currentHash;

    public SchedulerMock() {
        jobs = new JobService();
        metadata = new MetadataService();
        queries = new QueryService();
    }

    public SchedulerMock config(Scheduler_Config__mdt config) {
        metadata.configs.add(config);
        return this;
    }

    public SchedulerMock job(Scheduler__c job) {
        if (currentHash != null && job.Metadata_Hash__c == null) {
            job.Metadata_Hash__c = currentHash;
        }
        queries.jobs.add(job);
        return this;
    }

    public SchedulerMock seedCurrentHash() {
        currentHash = metadata.getHash(metadata.configs);
        for (Scheduler__c job : queries.jobs) {
            job.Metadata_Hash__c = currentHash;
        }
        return this;
    }

    public with sharing class JobService extends Scheduler.JobService {
        public List<Scheduler__c> ranJobs = new List<Scheduler__c>();

        public override void run(Scheduler__c job) {
            ranJobs.add(job);
            Scheduler task = (Scheduler) Type.forName(job.Apex__c).newInstance();
            task.setSchedulerJob(job.Id).execute(null);
        }
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
            if (keys == null || keys.isEmpty()) return rows;

            for (Scheduler__c job : jobs) {
                if (keys.contains(job.Config_Key__c)) {
                    rows.add(job);
                }
            }
            return rows;
        }

        public override List<Scheduler__c> getJobsByKeysAndMetadataHash(Set<String> keys, String metadataHash) {
            List<Scheduler__c> rows = new List<Scheduler__c>();
            if (keys == null || keys.isEmpty()) return rows;

            for (Scheduler__c job : jobs) {
                if (keys.contains(job.Config_Key__c) && job.Metadata_Hash__c == metadataHash) {
                    rows.add(job);
                }
            }
            return rows;
        }

        public override List<Scheduler__c> getJobsByMetadataHash(String metadataHash) {
            List<Scheduler__c> rows = new List<Scheduler__c>();
            for (Scheduler__c job : jobs) {
                if (job.Metadata_Hash__c == metadataHash) {
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
}
