public with sharing class SchedulerConsoleController {
    static final Integer REFRESH_INTERVAL_SECONDS = 15;

    @AuraEnabled
    public static ConsoleState getSchedule() {
        Datetime now = System.now();
        ConsoleState state = new ConsoleState();
        state.generatedAt = now;
        state.refreshIntervalSeconds = REFRESH_INTERVAL_SECONDS;
        state.hasMetadataChanges = Scheduler.metadata.hasChanged();
        state.metadataRecalculationAt = state.hasMetadataChanges ? nextHeartbeatAt(now) : null;

        for (Scheduler__c job : Scheduler.queries.getJobsNotInKeys(new Set<String>())) {
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
        if (job.Is_Enabled__c != true) return null;
        if (job.Last_Executed_At__c == null) return now;

        String unit = frequency(job.Frequency__c);
        Integer amount = interval(job.Frequency_Value__c, unit);

        if (unit == Scheduler.HOURS) return job.Last_Executed_At__c.addHours(amount);
        if (unit == Scheduler.DAYS) return job.Last_Executed_At__c.addDays(amount);
        return job.Last_Executed_At__c.addMinutes(amount);
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
        if (unit == Scheduler.MINUTES && amount < 5) return 5;
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
    }

    public class JobRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String configKey;
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
            this.configKey = job.Config_Key__c;
            this.apexClass = job.Apex__c;
            this.isEnabled = job.Is_Enabled__c == true;
            this.frequency = frequency(job.Frequency__c);
            Integer amount = interval(job.Frequency_Value__c, this.frequency);
            this.frequencyValue = String.valueOf(amount);
            this.cadence = cadenceLabel(this.frequency, amount);
            this.lastExecutedAt = job.Last_Executed_At__c;
            this.nextScheduledAt = SchedulerConsoleController.nextScheduledAt(job, now);
            this.hasError = !String.isBlank(job.Last_Error__c);
            this.lastError = job.Last_Error__c;
            this.status = SchedulerConsoleController.status(this.isEnabled, this.nextScheduledAt, now);
        }
    }
}
