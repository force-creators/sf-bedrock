public with sharing class AsyncErrorsController {
    @AuraEnabled
    public static List<ThreadGroup> getErrors() {
        List<Async__c> workItems = Database.query(
            'SELECT Id, Name, Apex__c, CreatedBy.Name, CreatedDate, Priority__c, Record_Id__c, Status__c, Thread__c, Error_Message__c, Error_Stack_Trace__c ' +
            'FROM Async__c ' +
            'WHERE Status__c = \'Error\' ' +
            'WITH USER_MODE ' +
            'ORDER BY Thread__c ASC, Priority__c DESC NULLS LAST, CreatedDate ASC ' +
            'LIMIT 500'
        );
        Map<Id, Thread__c> threadsById = BedrockConsoleSupport.asyncThreadsById(workItems);

        Map<String, ThreadGroup> groupsByThread = new Map<String, ThreadGroup>();
        List<ThreadGroup> groups = new List<ThreadGroup>();

        for (Async__c workItem : workItems) {
            String thread = BedrockConsoleSupport.asyncThreadLabel(workItem, threadsById, 'Unassigned');

            if (!groupsByThread.containsKey(thread)) {
                ThreadGroup groupRecord = new ThreadGroup(thread);
                groupsByThread.put(thread, groupRecord);
                groups.add(groupRecord);
            }

            ThreadGroup groupRecord = groupsByThread.get(thread);
            groupRecord.rows.add(new ErrorRow(workItem));
            groupRecord.status = String.valueOf(groupRecord.rows.size()) + (groupRecord.rows.size() == 1 ? ' job' : ' jobs');
        }

        return groups;
    }

    @AuraEnabled
    public static Integer retryErrors(List<Id> workItemIds) {
        assertCanRetry();

        List<Async__c> workItems = errorWorkItems(workItemIds);
        Set<Id> ids = Pluck.ids(workItems);
        Async.jobs.retry(ids);
        return ids.size();
    }

    @AuraEnabled
    public static Integer deleteErrors(List<Id> workItemIds) {
        assertCanDelete();

        List<Async__c> workItems = errorWorkItems(workItemIds);
        DML.deleteRecords(workItems);
        return workItems.size();
    }

    static List<Async__c> errorWorkItems(List<Id> workItemIds) {
        Set<Id> selectedIds = new Set<Id>();

        if (workItemIds != null) {
            selectedIds.addAll(workItemIds);
        }

        if (selectedIds.isEmpty()) {
            return new List<Async__c>();
        }

        return [
            SELECT Id
            FROM Async__c
            WHERE Id IN :selectedIds
                AND Status__c = 'Error'
            WITH USER_MODE
        ];
    }

    static void assertCanRetry() {
        if (
            !Schema.sObjectType.Async__c.isUpdateable() ||
            !Async__c.Status__c.getDescribe().isUpdateable() ||
            !Schema.sObjectType.Async__c.fields.getMap().get('Thread__c').getDescribe().isUpdateable()
        ) {
            throw new AuraHandledException('You do not have permission to retry async errors.');
        }
    }

    static void assertCanDelete() {
        if (!Schema.sObjectType.Async__c.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete async errors.');
        }
    }

    public class ThreadGroup {
        @AuraEnabled public String id;
        @AuraEnabled public String threadLabel;
        @AuraEnabled public String status;
        @AuraEnabled public List<ErrorRow> rows;

        ThreadGroup(String thread) {
            this.id = 'thread-' + thread.replaceAll('[^a-zA-Z0-9]+', '-').toLowerCase();
            this.threadLabel = thread;
            this.status = '0 jobs';
            this.rows = new List<ErrorRow>();
        }
    }

    public class ErrorRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String asyncJobNumber;
        @AuraEnabled public String runningUser;
        @AuraEnabled public String apexClass;
        @AuraEnabled public Decimal priority;
        @AuraEnabled public String recordId;
        @AuraEnabled public String status;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String errorStackTrace;
        @AuraEnabled public Datetime createdDate;

        ErrorRow(Async__c workItem) {
            this.id = workItem.Id;
            this.asyncJobNumber = workItem.Name;
            this.runningUser = workItem.CreatedBy.Name;
            this.apexClass = workItem.Apex__c;
            this.priority = workItem.Priority__c;
            this.recordId = workItem.Record_Id__c;
            this.status = workItem.Status__c;
            this.errorMessage = workItem.Error_Message__c;
            this.errorStackTrace = workItem.Error_Stack_Trace__c;
            this.createdDate = workItem.CreatedDate;
        }
    }
}
