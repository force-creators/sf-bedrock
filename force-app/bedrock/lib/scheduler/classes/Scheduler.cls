/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class Scheduler implements Queueable {
    public static final String EVERY_FIVE_MINUTES = 'Every 5 Minutes';
    public static final String MINUTES = 'Minutes';
    public static final String HOURS = 'Hours';
    public static final String DAYS = 'Days';
    public static final String WEEKS = 'Weeks';
    public static final String MONTHS = 'Months';
    public static JobService jobs = new JobService();
    public static MetadataService metadata = new MetadataService();
    public static QueryService queries = new QueryService();
    public Id schedulerJobId;

    @testVisible
    static void setMock(SchedulerMock mock) {
        jobs = mock.jobs;
        metadata = mock.metadata;
        queries = mock.queries;
    }

    @testVisible
    static void reset() {
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
        throw new SchedulerException(
            'Scheduler subclasses must override execute().'
        );
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
        if (schedulerJobId == null)
            return;

        jobs.updateRecords(
            new List<SObject>{
                new Scheduler__c(Id = schedulerJobId, Next_Run__c = nextRunAt)
            }
        );
    }

    static void recordResult(
        Id schedulerJobId,
        DateTime executedAt,
        String errorMessage
    ) {
        if (schedulerJobId == null)
            return;

        jobs.updateRecords(
            new List<SObject>{
                new Scheduler__c(
                    Id = schedulerJobId,
                    Last_Executed__c = executedAt,
                    Error_Message__c = truncateError(errorMessage)
                )
            }
        );
    }

    static void recordError(Id schedulerJobId, String errorMessage) {
        if (schedulerJobId == null)
            return;

        jobs.updateRecords(
            new List<SObject>{
                new Scheduler__c(
                    Id = schedulerJobId,
                    Error_Message__c = truncateError(errorMessage)
                )
            }
        );
    }

    static String truncateError(String message) {
        if (String.isBlank(message))
            return null;
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
                String label = minute < 10
                    ? '0' + String.valueOf(minute)
                    : String.valueOf(minute);
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
            DateTime heartbeatAt = getHeartbeatAt(now);
            for (Scheduler__c job : queries.getEnabledJobs()) {
                if (!isDue(job, heartbeatAt))
                    continue;
                try {
                    recordNextRun(job.Id, getNextRunAt(job, heartbeatAt));
                    run(job);
                } catch (Exception error) {
                    recordFailure(job, now, error);
                }
            }
        }

        public virtual void translateMetadata() {
            List<Scheduler_Job__mdt> configs = metadata.getConfigs();
            String metadataHash = metadata.getHash(configs);
            DateTime heartbeatAt = getHeartbeatAt(System.now());
            Map<String, Scheduler__c> jobsByApexClass = new Map<String, Scheduler__c>();

            for (
                Scheduler__c job : queries.getJobsByApexClasses(
                    metadata.getApexClasses(configs)
                )
            ) {
                jobsByApexClass.put(job.Apex__c, job);
            }

            List<SObject> jobs = new List<SObject>();
            Set<String> apexClasses = new Set<String>();

            for (Scheduler_Job__mdt config : configs) {
                String apexClass = config.Apex__c;
                apexClasses.add(apexClass);

                Scheduler__c job = jobsByApexClass.get(apexClass);
                Boolean isNew = job == null;
                Boolean wasEnabled = !isNew && job.Enabled__c == true;
                String previousFrequency = isNew ? null : job.Frequency__c;
                Decimal previousInterval = isNew ? null : job.Interval__c;
                if (isNew)
                    job = new Scheduler__c(Apex__c = apexClass);

                job.Apex__c = config.Apex__c;
                job.Enabled__c = config.Enabled__c;
                job.Hash__c = metadataHash;
                String unit = frequency(config.Frequency__c);
                Integer amount = interval(config.Interval__c, unit);
                job.Frequency__c = unit;
                job.Interval__c = amount;
                if (job.Enabled__c != true) {
                    job.Next_Run__c = null;
                } else if (
                    shouldResetNextRun(
                        isNew,
                        wasEnabled,
                        job,
                        previousFrequency,
                        previousInterval
                    )
                ) {
                    Boolean waitFromNow =
                        isNew ||
                        (!wasEnabled && job.Enabled__c == true) ||
                        job.Last_Executed__c == null;
                    job.Next_Run__c = getInitialNextRunAt(
                        job,
                        heartbeatAt,
                        unit,
                        amount,
                        waitFromNow
                    );
                }
                jobs.add(job);
            }

            for (
                Scheduler__c job : queries.getJobsNotInApexClasses(apexClasses)
            ) {
                job.Enabled__c = false;
                job.Hash__c = metadataHash;
                job.Next_Run__c = null;
                jobs.add(job);
            }

            if (!jobs.isEmpty()) {
                upsertRecords(jobs, Scheduler__c.Fields.Apex__c);
            }
        }

        public virtual void run(Scheduler__c job) {
            Scheduler task = (Scheduler) Type.forName(job.Apex__c)
                .newInstance();
            System.enqueueJob(task.setSchedulerJob(job.Id));
        }

        public virtual void recordFailure(
            Scheduler__c job,
            DateTime attemptedAt,
            Exception error
        ) {
            if (job.Id == null)
                return;

            Scheduler.recordError(job.Id, error.getMessage());
        }

        public virtual Boolean isDue(Scheduler__c job, DateTime now) {
            return job.Next_Run__c != null && job.Next_Run__c <= now;
        }

        Boolean shouldResetNextRun(
            Boolean isNew,
            Boolean wasEnabled,
            Scheduler__c job,
            String previousFrequency,
            Decimal previousInterval
        ) {
            if (isNew || job.Next_Run__c == null)
                return true;
            if (!wasEnabled && job.Enabled__c == true)
                return true;
            return previousFrequency != job.Frequency__c ||
                previousInterval != job.Interval__c;
        }

        DateTime getInitialNextRunAt(
            Scheduler__c job,
            DateTime now,
            String unit,
            Integer amount,
            Boolean waitFromNow
        ) {
            DateTime anchor = waitFromNow ? now : job.Last_Executed__c;
            return addInterval(anchor, unit, amount);
        }

        DateTime getNextRunAt(Scheduler__c job, DateTime now) {
            String unit = frequency(job.Frequency__c);
            Integer amount = interval(job.Interval__c, unit);
            return addInterval(now, unit, amount);
        }

        @testVisible
        DateTime getHeartbeatAt(DateTime now) {
            DateTime minuteAt = DateTime.newInstanceGMT(
                now.yearGmt(),
                now.monthGmt(),
                now.dayGmt(),
                now.hourGmt(),
                now.minuteGmt(),
                0
            );
            return minuteAt.addMinutes(-Math.mod(now.minuteGmt(), 5));
        }

        DateTime addInterval(DateTime anchor, String unit, Integer amount) {
            if (unit == HOURS)
                return anchor.addHours(amount);
            if (unit == DAYS)
                return anchor.addDays(amount);
            if (unit == WEEKS)
                return anchor.addDays(amount * 7);
            if (unit == MONTHS)
                return anchor.addMonths(amount);
            return anchor.addMinutes(amount);
        }

        String frequency(String value) {
            if (String.isBlank(value) || value == EVERY_FIVE_MINUTES)
                return MINUTES;
            return value;
        }

        Integer interval(String value) {
            if (String.isBlank(value))
                return 1;

            try {
                Integer amount = Integer.valueOf(value);
                return amount < 1 ? 1 : amount;
            } catch (Exception error) {
                return 1;
            }
        }

        Integer interval(Decimal value) {
            if (value == null)
                return 1;
            Integer amount = value.intValue();
            return amount < 1 ? 1 : amount;
        }

        @testVisible
        Integer interval(String value, String unit) {
            Integer amount = interval(value);
            if (unit == MINUTES)
                return Math.min(55, amount < 5 ? 5 : amount);
            if (unit == DAYS)
                return Math.min(31, amount);
            if (unit == WEEKS)
                return Math.min(52, amount);
            if (unit == MONTHS)
                return Math.min(12, amount);
            return amount;
        }

        @testVisible
        Integer interval(Decimal value, String unit) {
            Integer amount = interval(value);
            if (unit == MINUTES)
                return Math.min(55, amount < 5 ? 5 : amount);
            if (unit == DAYS)
                return Math.min(31, amount);
            if (unit == WEEKS)
                return Math.min(52, amount);
            if (unit == MONTHS)
                return Math.min(12, amount);
            return amount;
        }

        public virtual void attachFinalizer(Finalizer finalizer) {
            System.attachFinalizer(finalizer);
        }

        protected virtual void updateRecords(List<SObject> records) {
            update records;
        }

        protected virtual void upsertRecords(
            List<SObject> records,
            SObjectField externalIdField
        ) {
            Database.upsert(records, externalIdField, true);
        }
    }

    public virtual with sharing class MetadataService {
        public virtual List<Scheduler_Job__mdt> getConfigs() {
            return [
                SELECT
                    DeveloperName,
                    Apex__c,
                    Enabled__c,
                    Frequency__c,
                    Interval__c
                FROM Scheduler_Job__mdt
                ORDER BY DeveloperName
            ];
        }

        public virtual Set<String> getApexClasses(
            List<Scheduler_Job__mdt> configs
        ) {
            Set<String> apexClasses = new Set<String>();
            for (Scheduler_Job__mdt config : configs) {
                apexClasses.add(config.Apex__c);
            }
            return apexClasses;
        }

        public virtual Boolean hasChanged() {
            List<Scheduler_Job__mdt> configs = getConfigs();
            String currentHash = getHash(configs);
            Set<String> apexClasses = getApexClasses(configs);

            if (apexClasses.isEmpty()) {
                List<Scheduler__c> jobs = queries.getJobsNotInApexClasses(
                    apexClasses
                );
                if (jobs.isEmpty())
                    return false;
                return queries.getJobsByMetadataHash(currentHash).size() !=
                    jobs.size();
            }

            List<Scheduler__c> jobs = queries.getJobsByApexClassesAndMetadataHash(
                apexClasses,
                currentHash
            );
            if (jobs.size() != apexClasses.size())
                return true;

            for (Scheduler__c job : jobs) {
                if (job.Enabled__c == true && job.Next_Run__c == null)
                    return true;
            }
            return false;
        }

        public virtual String getHash(List<Scheduler_Job__mdt> configs) {
            return String.valueOf(System.hashCode(configs));
        }
    }

    public virtual with sharing class QueryService {
        public virtual List<Scheduler__c> getJobsByApexClasses(
            Set<String> apexClasses
        ) {
            if (apexClasses == null || apexClasses.isEmpty())
                return new List<Scheduler__c>();
            return [
                SELECT
                    Id,
                    Apex__c,
                    Enabled__c,
                    Frequency__c,
                    Interval__c,
                    Hash__c,
                    Next_Run__c,
                    Last_Executed__c,
                    Error_Message__c
                FROM Scheduler__c
                WHERE Apex__c IN :apexClasses
            ];
        }

        public virtual List<Scheduler__c> getJobsByApexClassesAndMetadataHash(
            Set<String> apexClasses,
            String metadataHash
        ) {
            if (apexClasses == null || apexClasses.isEmpty())
                return new List<Scheduler__c>();
            return [
                SELECT Id, Apex__c, Enabled__c, Hash__c, Next_Run__c
                FROM Scheduler__c
                WHERE Apex__c IN :apexClasses AND Hash__c = :metadataHash
            ];
        }

        public virtual List<Scheduler__c> getJobsByMetadataHash(
            String metadataHash
        ) {
            return [
                SELECT Id, Apex__c, Hash__c, Next_Run__c
                FROM Scheduler__c
                WHERE Hash__c = :metadataHash
            ];
        }

        public virtual List<Scheduler__c> getJobsNotInApexClasses(
            Set<String> apexClasses
        ) {
            if (apexClasses == null || apexClasses.isEmpty()) {
                return [
                    SELECT
                        Id,
                        Apex__c,
                        Enabled__c,
                        Frequency__c,
                        Interval__c,
                        Hash__c,
                        Next_Run__c,
                        Last_Executed__c,
                        Error_Message__c
                    FROM Scheduler__c
                ];
            }

            return [
                SELECT
                    Id,
                    Apex__c,
                    Enabled__c,
                    Frequency__c,
                    Interval__c,
                    Hash__c,
                    Next_Run__c,
                    Last_Executed__c,
                    Error_Message__c
                FROM Scheduler__c
                WHERE Apex__c NOT IN :apexClasses
            ];
        }

        public virtual List<Scheduler__c> getEnabledJobs() {
            return [
                SELECT
                    Id,
                    Apex__c,
                    Enabled__c,
                    Frequency__c,
                    Interval__c,
                    Hash__c,
                    Next_Run__c,
                    Last_Executed__c,
                    Error_Message__c
                FROM Scheduler__c
                WHERE Enabled__c = TRUE
                ORDER BY Apex__c
            ];
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

        @testVisible
        void recordResult(ParentJobResult result, Exception error) {
            if (result == ParentJobResult.SUCCESS)
                return;

            Scheduler.recordResult(
                schedulerJobId,
                System.now(),
                error == null ? String.valueOf(result) : error.getMessage()
            );
        }
    }

    public class SchedulerException extends Exception {
    }
}
