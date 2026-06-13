public with sharing class SchedulerConsoleController {
    static final Integer REFRESH_INTERVAL_SECONDS = 15;
    @testVisible static QueryService queries = new QueryService();

    @testVisible static void setQueryService(QueryService queryService) {
        queries = queryService;
    }

    @testVisible static void reset() {
        queries = new QueryService();
    }

    @AuraEnabled
    public static ConsoleState getSchedule() {
        Datetime now = System.now();
        ConsoleState state = new ConsoleState();
        state.generatedAt = now;
        state.refreshIntervalSeconds = REFRESH_INTERVAL_SECONDS;
        state.hasMetadataChanges = Scheduler.metadata.hasChanged();
        state.metadataRecalculationAt = state.hasMetadataChanges ? nextHeartbeatAt(now) : null;

        for (Scheduler__c job : queries.getJobs()) {
            JobRow row = new JobRow(job, now);
            state.jobs.add(row);

            if (row.isEnabled) {
                state.enabledJobCount++;
            } else {
                state.disabledJobCount++;
            }

            if (row.status == 'Due Now') {
                state.dueJobCount++;
            }

            if (row.hasError) {
                state.errorJobCount++;
            }
        }

        for (Scheduler_Job__mdt config : queries.getJobConfigurations()) {
            state.jobConfigurations.add(new JobConfigurationRow(config));
        }

        return state;
    }

    static Datetime nextHeartbeatAt(Datetime now) {
        Integer remainder = Math.mod(now.minute(), 5);
        Integer minutesToAdd = remainder == 0 && now.second() == 0 ? 0 : 5 - remainder;
        if (minutesToAdd == 0) return now;

        Datetime currentMinute = Datetime.newInstance(
            now.date(),
            Time.newInstance(now.hour(), now.minute(), 0, 0)
        );
        return currentMinute.addMinutes(minutesToAdd);
    }

    static Datetime nextScheduledAt(Scheduler__c job, Datetime now) {
        if (job.Enabled__c != true) return null;
        if (job.Next_Run__c != null) return job.Next_Run__c;
        if (job.Last_Executed__c == null) return now;

        String unit = frequency(job.Frequency__c);
        Integer amount = interval(job.Interval__c, unit);

        if (unit == Scheduler.HOURS) return job.Last_Executed__c.addHours(amount);
        if (unit == Scheduler.DAYS) return job.Last_Executed__c.addDays(amount);
        if (unit == Scheduler.WEEKS) return job.Last_Executed__c.addDays(amount * 7);
        if (unit == Scheduler.MONTHS) return job.Last_Executed__c.addMonths(amount);
        return job.Last_Executed__c.addMinutes(amount);
    }

    static String frequency(String value) {
        if (String.isBlank(value) || value == Scheduler.EVERY_FIVE_MINUTES) return Scheduler.MINUTES;
        return value;
    }

    static Integer interval(String value, String unit) {
        Integer amount = 1;

        if (!String.isBlank(value)) {
            try {
                amount = Integer.valueOf(value);
            } catch (Exception error) {
                amount = 1;
            }
        }

        if (amount < 1) amount = 1;
        if (unit == Scheduler.MINUTES) return Math.min(55, amount < 5 ? 5 : amount);
        if (unit == Scheduler.DAYS) return Math.min(31, amount);
        if (unit == Scheduler.WEEKS) return Math.min(52, amount);
        if (unit == Scheduler.MONTHS) return Math.min(12, amount);
        return amount;
    }

    static Integer interval(Decimal value, String unit) {
        Integer amount = value == null ? 1 : value.intValue();

        if (amount < 1) amount = 1;
        if (unit == Scheduler.MINUTES) return Math.min(55, amount < 5 ? 5 : amount);
        if (unit == Scheduler.DAYS) return Math.min(31, amount);
        if (unit == Scheduler.WEEKS) return Math.min(52, amount);
        if (unit == Scheduler.MONTHS) return Math.min(12, amount);
        return amount;
    }

    static String cadenceLabel(String unit, Integer amount) {
        String label = unit == Scheduler.MINUTES ? 'minute' : unit.toLowerCase().left(unit.length() - 1);
        return 'Every ' + String.valueOf(amount) + ' ' + label + (amount == 1 ? '' : 's');
    }

    static String status(Boolean isEnabled, Datetime nextScheduledAt, Datetime now) {
        if (!isEnabled) return 'Disabled';
        if (nextScheduledAt == null || nextScheduledAt <= now) return 'Due Now';
        return 'Scheduled';
    }

    public class ConsoleState {
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public Integer refreshIntervalSeconds;
        @AuraEnabled public Boolean hasMetadataChanges = false;
        @AuraEnabled public Datetime metadataRecalculationAt;
        @AuraEnabled public Integer enabledJobCount = 0;
        @AuraEnabled public Integer disabledJobCount = 0;
        @AuraEnabled public Integer dueJobCount = 0;
        @AuraEnabled public Integer errorJobCount = 0;
        @AuraEnabled public List<JobRow> jobs = new List<JobRow>();
        @AuraEnabled public List<JobConfigurationRow> jobConfigurations = new List<JobConfigurationRow>();
    }

    public virtual with sharing class QueryService {
        public virtual List<Scheduler__c> getJobs() {
            return (List<Scheduler__c>) Query.records([
                SELECT Id, Apex__c, Enabled__c, Frequency__c, Interval__c,
                    Next_Run__c, Last_Executed__c, Error_Message__c
                FROM Scheduler__c
                ORDER BY Next_Run__c ASC NULLS LAST, Apex__c ASC
            ]);
        }

        public virtual List<Scheduler_Job__mdt> getJobConfigurations() {
            return [
                SELECT Id, DeveloperName, MasterLabel, Apex__c, Enabled__c, Frequency__c, Interval__c
                FROM Scheduler_Job__mdt
                WITH USER_MODE
                ORDER BY DeveloperName ASC
                LIMIT 500
            ];
        }
    }

    public class JobConfigurationRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String apexClass;
        @AuraEnabled public Boolean isEnabled;
        @AuraEnabled public String frequency;
        @AuraEnabled public String frequencyValue;
        @AuraEnabled public String cadence;

        JobConfigurationRow(Scheduler_Job__mdt config) {
            this.id = config.Id;
            this.developerName = config.DeveloperName;
            this.label = config.MasterLabel;
            this.apexClass = config.Apex__c;
            this.isEnabled = config.Enabled__c;
            this.frequency = frequency(config.Frequency__c);
            Integer amount = interval(config.Interval__c, this.frequency);
            this.frequencyValue = String.valueOf(amount);
            this.cadence = cadenceLabel(this.frequency, amount);
        }
    }

    public class JobRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String apexClass;
        @AuraEnabled public Boolean isEnabled;
        @AuraEnabled public String frequency;
        @AuraEnabled public String frequencyValue;
        @AuraEnabled public String cadence;
        @AuraEnabled public Datetime lastExecutedAt;
        @AuraEnabled public Datetime nextScheduledAt;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean hasError;
        @AuraEnabled public String lastError;

        JobRow(Scheduler__c job, Datetime now) {
            this.id = job.Id;
            this.apexClass = job.Apex__c;
            this.isEnabled = job.Enabled__c == true;
            this.frequency = frequency(job.Frequency__c);
            Integer amount = interval(job.Interval__c, this.frequency);
            this.frequencyValue = String.valueOf(amount);
            this.cadence = cadenceLabel(this.frequency, amount);
            this.lastExecutedAt = job.Last_Executed__c;
            this.nextScheduledAt = SchedulerConsoleController.nextScheduledAt(job, now);
            this.hasError = !String.isBlank(job.Error_Message__c);
            this.lastError = job.Error_Message__c;
            this.status = SchedulerConsoleController.status(this.isEnabled, this.nextScheduledAt, now);
        }
    }
}
