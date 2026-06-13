public virtual with sharing class Scheduler implements Queueable {
    public static final String EVERY_FIVE_MINUTES = 'Every 5 Minutes';
    public static final String MINUTES = 'Minutes';
    public static final String HOURS = 'Hours';
    public static final String DAYS = 'Days';
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

    public static void schedule() {
        jobs.schedule();
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
            execute();
            recordExecution(attemptedAt, null);
        } catch (Exception error) {
            recordExecution(attemptedAt, error.getMessage());
        }
    }

    void recordExecution(DateTime attemptedAt, String errorMessage) {
        if (schedulerJobId == null) return;

        DML.updateRecords(new List<SObject> {
            new Scheduler__c(
                Id = schedulerJobId,
                Last_Executed_At__c = attemptedAt,
                Last_Error__c = truncateError(errorMessage)
            )
        });
    }

    static String truncateError(String message) {
        if (String.isBlank(message)) return null;
        return message.left(32768);
    }

    public virtual with sharing class JobService {
        public virtual void schedule() {
            for (CronTrigger cronTrigger : [
                SELECT Id
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE 'Bedrock Scheduler %'
            ]) {
                System.abortJob(cronTrigger.Id);
            }

            for (Integer minute = 0; minute < 60; minute += 5) {
                String label = minute < 10 ? '0' + String.valueOf(minute) : String.valueOf(minute);
                System.schedule(
                    'Bedrock Scheduler ' + label,
                    '0 ' + String.valueOf(minute) + ' * * * ? *',
                    new SchedulerTick()
                );
            }
        }

        public virtual void tick() {
            if (metadata.hasChanged()) {
                translateMetadata();
            }

            DateTime now = System.now();
            for (Scheduler__c job : queries.getEnabledJobs()) {
                if (!isDue(job, now)) continue;
                try {
                    run(job);
                } catch (Exception error) {
                    recordFailure(job, now, error);
                }
            }
        }

        public virtual void translateMetadata() {
            List<Scheduler_Config__mdt> configs = metadata.getConfigs();
            Map<String, Scheduler__c> jobsByKey = new Map<String, Scheduler__c>();

            for (Scheduler__c job : queries.getJobsByKeys(metadata.getConfigKeys(configs))) {
                jobsByKey.put(job.Config_Key__c, job);
            }

            List<SObject> jobs = new List<SObject>();
            Set<String> keys = new Set<String>();

            for (Scheduler_Config__mdt config : configs) {
                String key = config.DeveloperName;
                keys.add(key);

                Scheduler__c job = jobsByKey.get(key);
                if (job == null) job = new Scheduler__c(Config_Key__c = key);

                job.Apex__c = config.Apex__c;
                job.Is_Enabled__c = config.Is_Enabled__c;
                String unit = frequency(config.Frequency__c);
                job.Frequency__c = unit;
                job.Frequency_Value__c = String.valueOf(interval(config.Frequency_Value__c, unit));
                jobs.add(job);
            }

            for (Scheduler__c job : queries.getJobsNotInKeys(keys)) {
                job.Is_Enabled__c = false;
                jobs.add(job);
            }

            if (!jobs.isEmpty()) {
                DML.upsertRecords(jobs, Scheduler__c.Fields.Config_Key__c);
            }

            settings.saveHash(metadata.getHash(configs));
        }

        public virtual void run(Scheduler__c job) {
            Scheduler task = (Scheduler) Type.forName(job.Apex__c).newInstance();
            System.enqueueJob(task.setSchedulerJob(job.Id));
        }

        public virtual void recordFailure(Scheduler__c job, DateTime attemptedAt, Exception error) {
            if (job.Id == null) return;

            DML.updateRecords(new List<SObject> {
                new Scheduler__c(
                    Id = job.Id,
                    Last_Executed_At__c = attemptedAt,
                    Last_Error__c = truncateError(error.getMessage())
                )
            });
        }

        public virtual Boolean isDue(Scheduler__c job, DateTime now) {
            if (job.Last_Executed_At__c == null) return true;

            String unit = frequency(job.Frequency__c);
            Integer amount = interval(job.Frequency_Value__c, unit);

            if (unit == MINUTES) return job.Last_Executed_At__c <= now.addMinutes(-amount);
            if (unit == HOURS) return job.Last_Executed_At__c <= now.addHours(-amount);
            if (unit == DAYS) return job.Last_Executed_At__c <= now.addDays(-amount);
            return job.Last_Executed_At__c <= now.addMinutes(-amount);
        }

        String frequency(String value) {
            if (String.isBlank(value) || value == EVERY_FIVE_MINUTES) return MINUTES;
            return value;
        }

        Integer interval(String value) {
            if (String.isBlank(value)) return 1;

            try {
                Integer amount = Integer.valueOf(value);
                return amount < 1 ? 1 : amount;
            } catch (Exception error) {
                return 1;
            }
        }

        Integer interval(String value, String unit) {
            Integer amount = interval(value);
            if (unit == MINUTES && amount < 5) return 5;
            return amount;
        }
    }

    public virtual with sharing class MetadataService {
        public virtual List<Scheduler_Config__mdt> getConfigs() {
            return [
                SELECT DeveloperName, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c
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
            String currentHash = getHash(getConfigs());
            String previousHash = settings.getSettings().Metadata_Hash__c;
            return currentHash != previousHash;
        }

        public virtual String getHash(List<Scheduler_Config__mdt> configs) {
            return String.valueOf(System.hashCode(configs));
        }
    }

    public virtual with sharing class QueryService {
        public virtual List<Scheduler__c> getJobsByKeys(Set<String> keys) {
            if (keys == null || keys.isEmpty()) return new List<Scheduler__c>();
            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Config_Key__c IN :keys
            ]);
        }

        public virtual List<Scheduler__c> getJobsNotInKeys(Set<String> keys) {
            if (keys == null || keys.isEmpty()) {
                return (List<Scheduler__c>) Query.records([
                    SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c, Last_Executed_At__c, Last_Error__c
                    FROM Scheduler__c
                ]);
            }

            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Config_Key__c NOT IN :keys
            ]);
        }

        public virtual List<Scheduler__c> getEnabledJobs() {
            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Is_Enabled__c = true
                ORDER BY Config_Key__c
            ]);
        }
    }

    public virtual with sharing class SettingsService {
        Scheduler_Settings__c schedulerSettings;

        public virtual Scheduler_Settings__c getSettings() {
            if (schedulerSettings != null) return schedulerSettings;

            schedulerSettings = Scheduler_Settings__c.getOrgDefaults();
            if (schedulerSettings != null) return schedulerSettings;

            schedulerSettings = new Scheduler_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
            return schedulerSettings;
        }

        public virtual void saveHash(String hash) {
            Scheduler_Settings__c row = getSettings();
            row.Metadata_Hash__c = hash;
            row.Translated_At__c = System.now();
            DML.upsertRecords(new List<SObject> { row });
        }
    }

    public with sharing class ScheduleTick implements Schedulable {
        public void execute(SchedulableContext context) {
            Scheduler.tick();
        }
    }

    public class SchedulerException extends Exception {}
}
