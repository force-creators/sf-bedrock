public with sharing class EventConsoleController {
    static final Integer MAX_ROWS = 100;

    @AuraEnabled
    public static ConsoleState getState() {
        ConsoleState state = new ConsoleState();
        state.metrics = getMetrics();
        state.backlogRows = backlogRows();
        state.runningRows = runningRows();
        state.errorRows = errorRows();
        state.archiveRows = archiveRows();
        state.configRows = configRows();
        state.settings = new ConsoleSettings();
        return state;
    }

    static ConsoleMetrics getMetrics() {
        ConsoleMetrics metrics = new ConsoleMetrics();

        metrics.backlog = [
            SELECT COUNT()
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
                AND Status__c IN :backlogStatuses()
        ];

        metrics.running = [
            SELECT COUNT()
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
                AND Status__c = :EventRelay.RUNNING
        ];

        metrics.errors = [
            SELECT COUNT()
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
                AND Status__c = :EventRelay.ERROR
        ];

        metrics.publishedToday = [
            SELECT COUNT()
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
                AND Status__c = :EventRelay.DONE
                AND LastModifiedDate = TODAY
        ];

        return metrics;
    }

    static List<EventRow> backlogRows() {
        Set<String> statuses = backlogStatuses();

        return rowsFrom([
            SELECT Id, Name, Status__c, Job_Type__c, Route__c, Payload_Type__c,
                Thread__c, Thread__r.Name, Thread_Key__c, Retry_Count__c,
                Error_Message__c, CreatedBy.Name, CreatedDate, LastModifiedDate
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
                AND Status__c IN :statuses
            ORDER BY CreatedDate ASC, Order__c ASC, Name ASC
            LIMIT :MAX_ROWS
        ]);
    }

    static List<EventRow> runningRows() {
        return rowsFrom([
            SELECT Id, Name, Status__c, Job_Type__c, Route__c, Payload_Type__c,
                Thread__c, Thread__r.Name, Thread_Key__c, Retry_Count__c,
                Error_Message__c, CreatedBy.Name, CreatedDate, LastModifiedDate
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
                AND Status__c = :EventRelay.RUNNING
            ORDER BY LastModifiedDate DESC, CreatedDate ASC
            LIMIT :MAX_ROWS
        ]);
    }

    static List<EventRow> errorRows() {
        return rowsFrom([
            SELECT Id, Name, Status__c, Job_Type__c, Route__c, Payload_Type__c,
                Thread__c, Thread__r.Name, Thread_Key__c, Retry_Count__c,
                Error_Message__c, CreatedBy.Name, CreatedDate, LastModifiedDate
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
                AND Status__c = :EventRelay.ERROR
            ORDER BY LastModifiedDate DESC, CreatedDate DESC
            LIMIT :MAX_ROWS
        ]);
    }

    static List<EventRow> archiveRows() {
        return rowsFrom([
            SELECT Id, Name, Status__c, Job_Type__c, Route__c, Payload_Type__c,
                Thread__c, Thread__r.Name, Thread_Key__c, Retry_Count__c,
                Error_Message__c, CreatedBy.Name, CreatedDate, LastModifiedDate
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
                AND Status__c = :EventRelay.DONE
            ORDER BY LastModifiedDate DESC, CreatedDate DESC
            LIMIT :MAX_ROWS
        ]);
    }

    static List<ConfigRow> configRows() {
        List<ConfigRow> rows = new List<ConfigRow>();
        for (AggregateResult result : [
            SELECT Payload_Type__c payloadType, Route__c route, COUNT(Id) workItems
            FROM Event__c
            WHERE Job_Type__c = :EventRelay.PUBLISH
            GROUP BY Payload_Type__c, Route__c
            ORDER BY Payload_Type__c ASC, Route__c ASC
            LIMIT :MAX_ROWS
        ]) {
            rows.add(new ConfigRow(result));
        }
        return rows;
    }

    static Set<String> backlogStatuses() {
        return new Set<String>{ EventRelay.PENDING, EventRelay.PAUSED };
    }

    static List<EventRow> rowsFrom(List<Event__c> workItems) {
        List<EventRow> rows = new List<EventRow>();
        for (Event__c workItem : workItems) {
            rows.add(new EventRow(workItem));
        }
        return rows;
    }

    static String errorPreview(String message) {
        if (String.isBlank(message)) return null;
        if (message.length() <= 240) return message;
        return message.left(237) + '...';
    }

    public class ConsoleState {
        @AuraEnabled public ConsoleMetrics metrics;
        @AuraEnabled public List<EventRow> backlogRows;
        @AuraEnabled public List<EventRow> runningRows;
        @AuraEnabled public List<EventRow> errorRows;
        @AuraEnabled public List<EventRow> archiveRows;
        @AuraEnabled public List<ConfigRow> configRows;
        @AuraEnabled public ConsoleSettings settings;
    }

    public class ConsoleMetrics {
        @AuraEnabled public Integer backlog;
        @AuraEnabled public Integer running;
        @AuraEnabled public Integer errors;
        @AuraEnabled public Integer publishedToday;
    }

    public class ConsoleSettings {
        @AuraEnabled public Integer publishBatchSize;
        @AuraEnabled public Integer limitThresholdPct;
        @AuraEnabled public String publishPool;

        ConsoleSettings() {
            this.publishBatchSize = EventRelay.settings.batchSize();
            this.limitThresholdPct = EventRelay.settings.limitThresholdPct();
            this.publishPool = EventRelay.PUBLISH_POOL;
        }
    }

    public class ConfigRow {
        @AuraEnabled public String id;
        @AuraEnabled public String payloadType;
        @AuraEnabled public String route;
        @AuraEnabled public Integer workItems;

        ConfigRow(AggregateResult result) {
            this.payloadType = String.valueOf(result.get('payloadType'));
            this.route = String.valueOf(result.get('route'));
            this.workItems = (Integer) result.get('workItems');
            this.id = this.payloadType + ':' + this.route;
        }
    }

    public class EventRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String eventNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String jobType;
        @AuraEnabled public String route;
        @AuraEnabled public String payloadType;
        @AuraEnabled public Id threadId;
        @AuraEnabled public String threadName;
        @AuraEnabled public String threadKey;
        @AuraEnabled public Decimal retryCount;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String createdBy;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;

        EventRow(Event__c workItem) {
            this.id = workItem.Id;
            this.eventNumber = workItem.Name;
            this.status = workItem.Status__c;
            this.jobType = workItem.Job_Type__c;
            this.route = workItem.Route__c;
            this.payloadType = workItem.Payload_Type__c;
            this.threadId = workItem.Thread__c;
            this.threadName = workItem.Thread__r == null ? null : workItem.Thread__r.Name;
            this.threadKey = workItem.Thread_Key__c;
            this.retryCount = workItem.Retry_Count__c;
            this.errorMessage = errorPreview(workItem.Error_Message__c);
            this.createdBy = workItem.CreatedBy.Name;
            this.createdDate = workItem.CreatedDate;
            this.lastModifiedDate = workItem.LastModifiedDate;
        }
    }
}
