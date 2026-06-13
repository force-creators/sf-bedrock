public virtual with sharing class Scheduler implements Queueable {
    public static JobService jobs = new JobService();
    public static MetadataService metadata = new MetadataService();
    public static QueryService queries = new QueryService();
    public static SettingsService settings = new SettingsService();
    public Id schedulerJobId;

    @testVisible static void setMock(SchedulerMock mock) {
        jobs = mock.jobs;
        metadata = mock.metadata;
        queries = mock.queries;
        settings = mock.settings;
    }

    @testVisible static void reset() {
        jobs = new JobService();
        metadata = new MetadataService();
        queries = new QueryService();
        settings = new SettingsService();
    }

    public static void tick() {
        jobs.tick();
    }

    public static Id schedule() {
        return jobs.schedule();
    }

    public static String cron() {
        return '0 0/5 * * * ? *';
    }

    public Scheduler setSchedulerJob(Id schedulerJobId) {
        this.schedulerJobId = schedulerJobId;
        return this;
    }

    public virtual void execute() {
        throw new SchedulerException('Scheduler subclasses must override execute().');
    }

    public void execute(QueueableContext context) {
        DateTime attemptedAt = System.now();

        try {
            this.execute();
            this.recordExecution(attemptedAt, null);
        } catch (Exception error) {
            this.recordExecution(attemptedAt, error.getMessage());
        }
    }

    void recordExecution(DateTime attemptedAt, String errorMessage) {
        if (this.schedulerJobId == null) return;

        DML.updateRecords(new List<SObject> {
            new Scheduler__c(
                Id = this.schedulerJobId,
                Last_Executed_At__c = attemptedAt,
                Last_Error__c = truncateError(errorMessage)
            )
        });
    }

    String truncateError(String message) {
        if (String.isBlank(message)) return null;
        return message.left(32768);
    }

    public virtual with sharing class JobService {
        public virtual Id schedule() {
            return System.schedule('Bedrock Scheduler', Scheduler.cron(), new ScheduleTick());
        }

        public virtual void tick() {
            if (metadata.hasChanged()) {
                this.translateMetadata();
            }

            for (Scheduler__c job : queries.getRunnableJobs()) {
                this.run(job);
            }
        }

        public virtual void translateMetadata() {
            List<Scheduler_Config__mdt> configs = metadata.getConfigs();
            Map<String, Scheduler__c> existingJobsByKey = new Map<String, Scheduler__c>();

            for (Scheduler__c job : queries.getJobsByKeys(metadata.getConfigKeys(configs))) {
                existingJobsByKey.put(job.Config_Key__c, job);
            }

            List<SObject> jobsToUpsert = new List<SObject>();
            Set<String> activeKeys = new Set<String>();

            for (Scheduler_Config__mdt config : configs) {
                activeKeys.add(config.DeveloperName);

                Scheduler__c job = existingJobsByKey.get(config.DeveloperName);
                if (job == null) {
                    job = new Scheduler__c(Config_Key__c = config.DeveloperName);
                }

                job.Apex__c = config.Apex__c;
                job.Is_Enabled__c = config.Is_Enabled__c;
                jobsToUpsert.add(job);
            }

            for (Scheduler__c staleJob : queries.getJobsNotInKeys(activeKeys)) {
                staleJob.Is_Enabled__c = false;
                jobsToUpsert.add(staleJob);
            }

            if (!jobsToUpsert.isEmpty()) {
                DML.upsertRecords(jobsToUpsert, Scheduler__c.Fields.Config_Key__c);
            }

            settings.saveHash(metadata.getHash(configs));
        }

        public virtual void run(Scheduler__c job) {
            Scheduler task = (Scheduler) Type.forName(job.Apex__c).newInstance();
            System.enqueueJob(task.setSchedulerJob(job.Id));
        }
    }

    public virtual with sharing class MetadataService {
        public virtual List<Scheduler_Config__mdt> getConfigs() {
            return [
                SELECT DeveloperName, Apex__c, Is_Enabled__c
                FROM Scheduler_Config__mdt
                ORDER BY DeveloperName
            ];
        }

        public virtual Set<String> getConfigKeys(List<Scheduler_Config__mdt> configs) {
            Set<String> keys = new Set<String>();

            for (Scheduler_Config__mdt config : configs) {
                keys.add(config.DeveloperName);
            }

            return keys;
        }

        public virtual Boolean hasChanged() {
            String currentHash = this.getHash(this.getConfigs());
            String previousHash = settings.getSettings().Metadata_Hash__c;
            return currentHash != previousHash;
        }

        public virtual String getHash(List<Scheduler_Config__mdt> configs) {
            List<String> parts = new List<String>();

            for (Scheduler_Config__mdt config : configs) {
                parts.add(String.join(new List<String> {
                    config.DeveloperName,
                    String.valueOf(config.Apex__c),
                    String.valueOf(config.Is_Enabled__c)
                }, '|'));
            }

            Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(String.join(parts, '\n')));
            return EncodingUtil.convertToHex(digest);
        }
    }

    public virtual with sharing class QueryService {
        public virtual List<Scheduler__c> getJobsByKeys(Set<String> keys) {
            if (keys == null || keys.isEmpty()) return new List<Scheduler__c>();

            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Config_Key__c IN :keys
            ]);
        }

        public virtual List<Scheduler__c> getJobsNotInKeys(Set<String> keys) {
            if (keys == null || keys.isEmpty()) {
                return (List<Scheduler__c>) Query.records([
                    SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Last_Executed_At__c, Last_Error__c
                    FROM Scheduler__c
                ]);
            }

            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Config_Key__c NOT IN :keys
            ]);
        }

        public virtual List<Scheduler__c> getRunnableJobs() {
            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Is_Enabled__c = true
                ORDER BY Config_Key__c
            ]);
        }
    }

    public virtual with sharing class SettingsService {
        Scheduler_Settings__c schedulerSettings;

        public virtual Scheduler_Settings__c getSettings() {
            if (this.schedulerSettings == null) {
                this.schedulerSettings = Scheduler_Settings__c.getOrgDefaults();

                if (this.schedulerSettings == null) {
                    this.schedulerSettings = new Scheduler_Settings__c(
                        SetupOwnerId = UserInfo.getOrganizationId()
                    );
                }
            }

            return this.schedulerSettings;
        }

        public virtual void saveHash(String hash) {
            Scheduler_Settings__c settings = this.getSettings();
            settings.Metadata_Hash__c = hash;
            settings.Translated_At__c = System.now();
            DML.upsertRecords(new List<SObject> { settings });
        }
    }

    public with sharing class ScheduleTick implements Schedulable {
        public void execute(SchedulableContext context) {
            Scheduler.tick();
        }
    }

    public class SchedulerException extends Exception {}
}
