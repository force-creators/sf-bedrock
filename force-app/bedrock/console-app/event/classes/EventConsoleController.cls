/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class EventConsoleController {
    static final Integer MAX_ROWS = 100;
    @testVisible
    static QueryService queries = new QueryService();

    @testVisible
    static void setQueryService(QueryService queryService) {
        queries = queryService;
    }

    @testVisible
    static void reset() {
        queries = new QueryService();
    }

    @AuraEnabled
    public static ConsoleState getState() {
        ConsoleState state = new ConsoleState();
        state.metrics = getMetrics();
        state.backlogRows = backlogRows();
        state.runningRows = runningRows();
        state.errorRows = errorRows();
        state.completedRows = completedRows();
        state.archiveRows = archiveRows();
        state.configRows = configRows();
        state.settings = new ConsoleSettings();
        return state;
    }

    @AuraEnabled
    public static Integer retryWorkItems(List<Id> workItemIds) {
        assertCanRetry();

        List<Event__c> workItems = queries.getErrorWorkItems(workItemIds);
        Set<Id> ids = Pluck.ids(workItems);
        EventRelay.retry(ids);
        return ids.size();
    }

    @AuraEnabled
    public static Integer deleteWorkItems(List<Id> workItemIds) {
        assertCanDelete();

        List<Event__c> workItems = queries.getErrorWorkItems(workItemIds);
        delete workItems;
        return workItems.size();
    }

    static void assertCanRetry() {
        if (!Schema.sObjectType.Event__c.isUpdateable()) {
            throw new AuraHandledException(
                'You do not have permission to retry event errors.'
            );
        }
    }

    static void assertCanDelete() {
        if (!Schema.sObjectType.Event__c.isDeletable()) {
            throw new AuraHandledException(
                'You do not have permission to delete event errors.'
            );
        }
    }

    static ConsoleMetrics getMetrics() {
        ConsoleMetrics metrics = new ConsoleMetrics();
        metrics.backlog = queries.countBacklog();
        metrics.running = queries.countRunning();
        metrics.errors = queries.countErrors();
        metrics.publishedToday = queries.countPublishedToday();
        return metrics;
    }

    static List<EventRow> backlogRows() {
        return rowsFrom(queries.getBacklogRows());
    }

    static List<EventRow> runningRows() {
        return rowsFrom(queries.getRunningRows());
    }

    static List<EventRow> errorRows() {
        return rowsFrom(queries.getErrorRows());
    }

    static List<EventRow> archiveRows() {
        return rowsFrom(queries.getArchiveRows());
    }

    static List<EventRow> completedRows() {
        return rowsFrom(queries.getCompletedRows());
    }

    static List<ConfigRow> configRows() {
        List<ConfigRow> rows = new List<ConfigRow>();
        for (AggregateResult result : queries.getConfigRows()) {
            rows.add(new ConfigRow(result));
        }
        return rows;
    }

    static Set<String> backlogStatuses() {
        return new Set<String>{ EventRelay.consts.PENDING };
    }

    static List<EventRow> rowsFrom(List<Event__c> workItems) {
        List<EventRow> rows = new List<EventRow>();
        for (Event__c workItem : workItems) {
            rows.add(new EventRow(workItem));
        }
        return rows;
    }

    static String errorPreview(String message) {
        return BedrockConsoleSupport.preview(message, 240);
    }

    public class ConsoleState {
        @AuraEnabled
        public ConsoleMetrics metrics;
        @AuraEnabled
        public List<EventRow> backlogRows;
        @AuraEnabled
        public List<EventRow> runningRows;
        @AuraEnabled
        public List<EventRow> errorRows;
        @AuraEnabled
        public List<EventRow> completedRows;
        @AuraEnabled
        public List<EventRow> archiveRows;
        @AuraEnabled
        public List<ConfigRow> configRows;
        @AuraEnabled
        public ConsoleSettings settings;
    }

    public virtual with sharing class QueryService {
        public virtual Integer countBacklog() {
            String publishJobType = EventRelay.consts.PUBLISH;
            return [
                SELECT COUNT()
                FROM Event__c
                WHERE
                    Job_Type__c = :publishJobType
                    AND Status__c IN :backlogStatuses()
            ];
        }

        public virtual Integer countRunning() {
            String publishJobType = EventRelay.consts.PUBLISH;
            String runningStatus = EventRelay.consts.RUNNING;
            return [
                SELECT COUNT()
                FROM Event__c
                WHERE
                    Job_Type__c = :publishJobType
                    AND Status__c = :runningStatus
            ];
        }

        public virtual Integer countErrors() {
            String publishJobType = EventRelay.consts.PUBLISH;
            String errorStatus = EventRelay.consts.ERROR;
            return [
                SELECT COUNT()
                FROM Event__c
                WHERE Job_Type__c = :publishJobType AND Status__c = :errorStatus
            ];
        }

        public virtual Integer countPublishedToday() {
            String publishJobType = EventRelay.consts.PUBLISH;
            String doneStatus = EventRelay.consts.DONE;
            return [
                SELECT COUNT()
                FROM Event__c
                WHERE
                    Job_Type__c = :publishJobType
                    AND Status__c = :doneStatus
                    AND LastModifiedDate = TODAY
            ];
        }

        public virtual List<Event__c> getBacklogRows() {
            Set<String> statuses = backlogStatuses();
            String publishJobType = EventRelay.consts.PUBLISH;
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Job_Type__c,
                    Route__c,
                    Payload_Type__c,
                    Idempotency_Key__c,
                    Thread__c,
                    Thread__r.Name,
                    Thread_Key__c,
                    Retry_Count__c,
                    Error_Message__c,
                    CreatedBy.Name,
                    CreatedDate,
                    LastModifiedDate
                FROM Event__c
                WHERE Job_Type__c = :publishJobType AND Status__c IN :statuses
                ORDER BY CreatedDate ASC, Order__c ASC, Name ASC
                LIMIT :MAX_ROWS
            ];
        }

        public virtual List<Event__c> getRunningRows() {
            String publishJobType = EventRelay.consts.PUBLISH;
            String runningStatus = EventRelay.consts.RUNNING;
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Job_Type__c,
                    Route__c,
                    Payload_Type__c,
                    Idempotency_Key__c,
                    Thread__c,
                    Thread__r.Name,
                    Thread_Key__c,
                    Retry_Count__c,
                    Error_Message__c,
                    CreatedBy.Name,
                    CreatedDate,
                    LastModifiedDate
                FROM Event__c
                WHERE
                    Job_Type__c = :publishJobType
                    AND Status__c = :runningStatus
                ORDER BY LastModifiedDate DESC, CreatedDate ASC
                LIMIT :MAX_ROWS
            ];
        }

        public virtual List<Event__c> getErrorRows() {
            String publishJobType = EventRelay.consts.PUBLISH;
            String errorStatus = EventRelay.consts.ERROR;
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Job_Type__c,
                    Route__c,
                    Payload_Type__c,
                    Idempotency_Key__c,
                    Thread__c,
                    Thread__r.Name,
                    Thread_Key__c,
                    Retry_Count__c,
                    Error_Message__c,
                    CreatedBy.Name,
                    CreatedDate,
                    LastModifiedDate
                FROM Event__c
                WHERE Job_Type__c = :publishJobType AND Status__c = :errorStatus
                ORDER BY LastModifiedDate DESC, CreatedDate DESC
                LIMIT :MAX_ROWS
            ];
        }

        public virtual List<Event__c> getArchiveRows() {
            String publishJobType = EventRelay.consts.PUBLISH;
            String staleStatus = EventRelay.consts.STALE;
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Job_Type__c,
                    Route__c,
                    Payload_Type__c,
                    Idempotency_Key__c,
                    Thread__c,
                    Thread__r.Name,
                    Thread_Key__c,
                    Retry_Count__c,
                    Error_Message__c,
                    CreatedBy.Name,
                    CreatedDate,
                    LastModifiedDate
                FROM Event__c
                WHERE Job_Type__c = :publishJobType AND Status__c = :staleStatus
                ORDER BY LastModifiedDate DESC, CreatedDate DESC
                LIMIT :MAX_ROWS
            ];
        }

        public virtual List<Event__c> getCompletedRows() {
            String publishJobType = EventRelay.consts.PUBLISH;
            String doneStatus = EventRelay.consts.DONE;
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Job_Type__c,
                    Route__c,
                    Payload_Type__c,
                    Idempotency_Key__c,
                    Thread__c,
                    Thread__r.Name,
                    Thread_Key__c,
                    Retry_Count__c,
                    Error_Message__c,
                    CreatedBy.Name,
                    CreatedDate,
                    LastModifiedDate
                FROM Event__c
                WHERE Job_Type__c = :publishJobType AND Status__c = :doneStatus
                ORDER BY LastModifiedDate DESC, CreatedDate DESC
                LIMIT :MAX_ROWS
            ];
        }

        public virtual List<AggregateResult> getConfigRows() {
            String publishJobType = EventRelay.consts.PUBLISH;
            return [
                SELECT
                    Payload_Type__c payloadType,
                    Route__c route,
                    COUNT(Id) workItems
                FROM Event__c
                WHERE Job_Type__c = :publishJobType
                GROUP BY Payload_Type__c, Route__c
                ORDER BY Payload_Type__c ASC, Route__c ASC
                LIMIT :MAX_ROWS
            ];
        }

        public virtual List<Event__c> getErrorWorkItems(List<Id> workItemIds) {
            Set<Id> selectedIds = new Set<Id>();
            String publishJobType = EventRelay.consts.PUBLISH;
            String errorStatus = EventRelay.consts.ERROR;

            if (workItemIds != null) {
                selectedIds.addAll(workItemIds);
            }

            if (selectedIds.isEmpty()) {
                return new List<Event__c>();
            }

            return [
                SELECT Id
                FROM Event__c
                WHERE
                    Id IN :selectedIds
                    AND Job_Type__c = :publishJobType
                    AND Status__c = :errorStatus
            ];
        }
    }

    public class ConsoleMetrics {
        @AuraEnabled
        public Integer backlog;
        @AuraEnabled
        public Integer running;
        @AuraEnabled
        public Integer errors;
        @AuraEnabled
        public Integer publishedToday;
    }

    public class ConsoleSettings {
        @AuraEnabled
        public Integer publishBatchSize;
        @AuraEnabled
        public Integer limitThresholdPct;
        @AuraEnabled
        public String publishPool;

        ConsoleSettings() {
            this.publishBatchSize = EventRelay.settings.batchSize();
            this.limitThresholdPct = EventRelay.settings.limitThresholdPct();
            this.publishPool = EventRelay.consts.PUBLISH_POOL;
        }
    }

    public class ConfigRow {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String payloadType;
        @AuraEnabled
        public String route;
        @AuraEnabled
        public Integer workItems;

        ConfigRow(AggregateResult result) {
            this.payloadType = String.valueOf(result.get('payloadType'));
            this.route = String.valueOf(result.get('route'));
            this.workItems = (Integer) result.get('workItems');
            this.id = this.payloadType + ':' + this.route;
        }
    }

    public class EventRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String eventNumber;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String jobType;
        @AuraEnabled
        public String route;
        @AuraEnabled
        public String payloadType;
        @AuraEnabled
        public String idempotencyKey;
        @AuraEnabled
        public Id threadId;
        @AuraEnabled
        public String threadName;
        @AuraEnabled
        public String threadKey;
        @AuraEnabled
        public Decimal retryCount;
        @AuraEnabled
        public String errorMessage;
        @AuraEnabled
        public String createdBy;
        @AuraEnabled
        public Datetime createdDate;
        @AuraEnabled
        public Datetime lastModifiedDate;

        EventRow(Event__c workItem) {
            this.id = workItem.Id;
            this.eventNumber = workItem.Name;
            this.status = workItem.Status__c;
            this.jobType = workItem.Job_Type__c;
            this.route = workItem.Route__c;
            this.payloadType = workItem.Payload_Type__c;
            this.idempotencyKey = workItem.Idempotency_Key__c;
            this.threadId = workItem.Thread__c;
            this.threadName = workItem.Thread__r == null
                ? null
                : workItem.Thread__r.Name;
            this.threadKey = workItem.Thread_Key__c;
            this.retryCount = workItem.Retry_Count__c;
            this.errorMessage = errorPreview(workItem.Error_Message__c);
            this.createdBy = workItem.CreatedBy.Name;
            this.createdDate = workItem.CreatedDate;
            this.lastModifiedDate = workItem.LastModifiedDate;
        }
    }
}
