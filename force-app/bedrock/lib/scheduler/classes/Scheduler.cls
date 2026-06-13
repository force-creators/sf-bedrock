public virtual with sharing class Scheduler implements Queueable {
    public static final String EVERY_FIVE_MINUTES = 'Every 5 Minutes';
    public static final String MINUTES = 'Minutes';
    public static final String HOURS = 'Hours';
    public static final String DAYS = 'Days';
    public static JobService jobs = new JobService();
    public static MetadataService metadata = new MetadataService();
    public static QueryService queries = new QueryService();
    public Id schedulerJobId;

    @testVisible static void setMock(SchedulerMock mock) {
        jobs = mock.jobs;
        metadata = mock.metadata;
        queries = mock.queries;
    }

    @testVisible static void reset() {
        jobs = new JobService();
        metadata = new MetadataService();
        queries = new QueryService();
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
        if (context != null && schedulerJobId != null) {
            jobs.attachFinalizer(new JobFinalizer(schedulerJobId));
        }

        try {
            execute();
            recordResult(System.now(), null);
        } catch (Exception error) {
            recordResult(System.now(), error.getMessage());
        }
    }

    void recordResult(DateTime executedAt, String errorMessage) {
        recordResult(schedulerJobId, executedAt, errorMessage);
    }

    static void recordNextRun(Id schedulerJobId, DateTime nextRunAt) {
        if (schedulerJobId == null) return;

        DML.updateRecords(new List<SObject> {
            new Scheduler__c(
                Id = schedulerJobId,
                Next_Run_At__c = nextRunAt
            )
        });
    }

    static void recordResult(Id schedulerJobId, DateTime executedAt, String errorMessage) {
        if (schedulerJobId == null) return;

        DML.updateRecords(new List<SObject> {
            new Scheduler__c(
                Id = schedulerJobId,
                Last_Executed_At__c = executedAt,
                Last_Error__c = truncateError(errorMessage)
            )
        });
    }

    static void recordError(Id schedulerJobId, String errorMessage) {
        if (schedulerJobId == null) return;

        DML.updateRecords(new List<SObject> {
            new Scheduler__c(
                Id = schedulerJobId,
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
                    recordNextRun(job.Id, getNextRunAt(job, now));
                    run(job);
                } catch (Exception error) {
                    recordFailure(job, now, error);
                }
            }
        }

        public virtual void translateMetadata() {
            List<Scheduler_Config__mdt> configs = metadata.getConfigs();
            String metadataHash = metadata.getHash(configs);
            DateTime now = System.now();
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
                Boolean isNew = job == null;
                Boolean wasEnabled = !isNew && job.Is_Enabled__c == true;
                String previousFrequency = isNew ? null : job.Frequency__c;
                String previousValue = isNew ? null : job.Frequency_Value__c;
                if (isNew) job = new Scheduler__c(Config_Key__c = key);

                job.Apex__c = config.Apex__c;
                job.Is_Enabled__c = config.Is_Enabled__c;
                job.Metadata_Hash__c = metadataHash;
                String unit = frequency(config.Frequency__c);
                String value = String.valueOf(interval(config.Frequency_Value__c, unit));
                job.Frequency__c = unit;
                job.Frequency_Value__c = value;
                if (job.Is_Enabled__c != true) {
                    job.Next_Run_At__c = null;
                } else if (shouldResetNextRun(isNew, wasEnabled, job, previousFrequency, previousValue)) {
                    Boolean waitFromNow = isNew || (!wasEnabled && job.Is_Enabled__c == true) || job.Last_Executed_At__c == null;
                    job.Next_Run_At__c = getInitialNextRunAt(job, now, unit, Integer.valueOf(value), waitFromNow);
                }
                jobs.add(job);
            }

            for (Scheduler__c job : queries.getJobsNotInKeys(keys)) {
                job.Is_Enabled__c = false;
                job.Metadata_Hash__c = metadataHash;
                job.Next_Run_At__c = null;
                jobs.add(job);
            }

            if (!jobs.isEmpty()) {
                DML.upsertRecords(jobs, Scheduler__c.Fields.Config_Key__c);
            }
        }

        public virtual void run(Scheduler__c job) {
            Scheduler task = (Scheduler) Type.forName(job.Apex__c).newInstance();
            System.enqueueJob(task.setSchedulerJob(job.Id));
        }

        public virtual void recordFailure(Scheduler__c job, DateTime attemptedAt, Exception error) {
            if (job.Id == null) return;

            Scheduler.recordError(job.Id, error.getMessage());
        }

        public virtual Boolean isDue(Scheduler__c job, DateTime now) {
            return job.Next_Run_At__c != null && job.Next_Run_At__c <= now;
        }

        Boolean shouldResetNextRun(Boolean isNew, Boolean wasEnabled, Scheduler__c job, String previousFrequency, String previousValue) {
            if (isNew || job.Next_Run_At__c == null) return true;
            if (!wasEnabled && job.Is_Enabled__c == true) return true;
            return previousFrequency != job.Frequency__c || previousValue != job.Frequency_Value__c;
        }

        DateTime getInitialNextRunAt(Scheduler__c job, DateTime now, String unit, Integer amount, Boolean waitFromNow) {
            DateTime anchor = waitFromNow ? now : job.Last_Executed_At__c;
            return addInterval(anchor, unit, amount);
        }

        DateTime getNextRunAt(Scheduler__c job, DateTime now) {
            String unit = frequency(job.Frequency__c);
            Integer amount = interval(job.Frequency_Value__c, unit);
            return addInterval(now, unit, amount);
        }

        DateTime addInterval(DateTime anchor, String unit, Integer amount) {
            if (unit == HOURS) return anchor.addHours(amount);
            if (unit == DAYS) return anchor.addDays(amount);
            return anchor.addMinutes(amount);
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

        public virtual void attachFinalizer(Finalizer finalizer) {
            System.attachFinalizer(finalizer);
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
            List<Scheduler_Config__mdt> configs = getConfigs();
            String currentHash = getHash(configs);
            Set<String> keys = getConfigKeys(configs);

            if (keys.isEmpty()) {
                List<Scheduler__c> jobs = queries.getJobsNotInKeys(keys);
                if (jobs.isEmpty()) return false;
                return queries.getJobsByMetadataHash(currentHash).size() != jobs.size();
            }

            List<Scheduler__c> jobs = queries.getJobsByKeysAndMetadataHash(keys, currentHash);
            if (jobs.size() != keys.size()) return true;

            for (Scheduler__c job : jobs) {
                if (job.Is_Enabled__c == true && job.Next_Run_At__c == null) return true;
            }
            return false;
        }

        public virtual String getHash(List<Scheduler_Config__mdt> configs) {
            return String.valueOf(System.hashCode(configs));
        }
    }

    public virtual with sharing class QueryService {
        public virtual List<Scheduler__c> getJobsByKeys(Set<String> keys) {
            if (keys == null || keys.isEmpty()) return new List<Scheduler__c>();
            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c, Metadata_Hash__c, Next_Run_At__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Config_Key__c IN :keys
            ]);
        }

        public virtual List<Scheduler__c> getJobsByKeysAndMetadataHash(Set<String> keys, String metadataHash) {
            if (keys == null || keys.isEmpty()) return new List<Scheduler__c>();
            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Is_Enabled__c, Metadata_Hash__c, Next_Run_At__c
                FROM Scheduler__c
                WHERE Config_Key__c IN :keys
                AND Metadata_Hash__c = :metadataHash
            ]);
        }

        public virtual List<Scheduler__c> getJobsByMetadataHash(String metadataHash) {
            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Metadata_Hash__c, Next_Run_At__c
                FROM Scheduler__c
                WHERE Metadata_Hash__c = :metadataHash
            ]);
        }

        public virtual List<Scheduler__c> getJobsNotInKeys(Set<String> keys) {
            if (keys == null || keys.isEmpty()) {
                return (List<Scheduler__c>) Query.records([
                    SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c, Metadata_Hash__c, Next_Run_At__c, Last_Executed_At__c, Last_Error__c
                    FROM Scheduler__c
                ]);
            }

            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c, Metadata_Hash__c, Next_Run_At__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Config_Key__c NOT IN :keys
            ]);
        }

        public virtual List<Scheduler__c> getEnabledJobs() {
            return (List<Scheduler__c>) Query.records([
                SELECT Id, Config_Key__c, Apex__c, Is_Enabled__c, Frequency__c, Frequency_Value__c, Metadata_Hash__c, Next_Run_At__c, Last_Executed_At__c, Last_Error__c
                FROM Scheduler__c
                WHERE Is_Enabled__c = true
                ORDER BY Config_Key__c
            ]);
        }
    }

    public with sharing class ScheduleTick implements Schedulable {
        public void execute(SchedulableContext context) {
            Scheduler.tick();
        }
    }

    public with sharing class JobFinalizer implements Finalizer {
        Id schedulerJobId;

        public JobFinalizer(Id schedulerJobId) {
            this.schedulerJobId = schedulerJobId;
        }

        public void execute(FinalizerContext context) {
            recordResult(context.getResult(), context.getException());
        }

        @testVisible void recordResult(ParentJobResult result, Exception error) {
            if (result == ParentJobResult.SUCCESS) return;

            Scheduler.recordResult(
                schedulerJobId,
                System.now(),
                error == null ? String.valueOf(result) : error.getMessage()
            );
        }
    }

    public class SchedulerException extends Exception {}
}
