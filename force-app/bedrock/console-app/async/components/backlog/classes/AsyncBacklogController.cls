public with sharing class AsyncBacklogController {
    @AuraEnabled
    public static List<ThreadGroup> getBacklog() {
        List<Async__c> workItems = Database.query(
            'SELECT Id, Name, Apex__c, CreatedBy.Name, CreatedDate, Priority__c, Record_Id__c, Status__c, Thread__c ' +
            'FROM Async__c ' +
            'WHERE Status__c NOT IN (\'Done\', \'Error\') ' +
            'ORDER BY Thread__c ASC, Priority__c DESC NULLS LAST, CreatedDate ASC ' +
            'LIMIT 500'
        );
        Map<Id, Thread__c> threadsById = threadsById(workItems);

        Map<String, ThreadGroup> groupsByThread = new Map<String, ThreadGroup>();
        List<ThreadGroup> groups = new List<ThreadGroup>();

        for (Async__c workItem : workItems) {
            String thread = threadLabel(workItem, threadsById);

            if (!groupsByThread.containsKey(thread)) {
                ThreadGroup groupRecord = new ThreadGroup(thread);
                groupsByThread.put(thread, groupRecord);
                groups.add(groupRecord);
            }

            ThreadGroup groupRecord = groupsByThread.get(thread);
            groupRecord.rows.add(new BacklogRow(workItem));
            groupRecord.status = String.valueOf(groupRecord.rows.size()) + (groupRecord.rows.size() == 1 ? ' job' : ' jobs');
        }

        return groups;
    }

    static Map<Id, Thread__c> threadsById(List<Async__c> workItems) {
        Set<Id> threadIds = new Set<Id>();
        for (Async__c workItem : workItems) {
            if (workItem.get('Thread__c') != null) {
                threadIds.add((Id) workItem.get('Thread__c'));
            }
        }
        return threadIds.isEmpty() ? new Map<Id, Thread__c>() : new Map<Id, Thread__c>([
            SELECT Id, Name
            FROM Thread__c
            WHERE Id IN :threadIds
        ]);
    }

    static String threadLabel(Async__c workItem, Map<Id, Thread__c> threadsById) {
        Id threadId = (Id) workItem.get('Thread__c');
        if (threadId == null || !threadsById.containsKey(threadId)) return 'Unassigned';
        return threadsById.get(threadId).Name;
    }

    public class ThreadGroup {
        @AuraEnabled public String id;
        @AuraEnabled public String threadLabel;
        @AuraEnabled public String status;
        @AuraEnabled public List<BacklogRow> rows;

        ThreadGroup(String thread) {
            this.id = 'thread-' + thread.replaceAll('[^a-zA-Z0-9]+', '-').toLowerCase();
            this.threadLabel = thread;
            this.status = '0 jobs';
            this.rows = new List<BacklogRow>();
        }
    }

    public class BacklogRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String asyncJobNumber;
        @AuraEnabled public String runningUser;
        @AuraEnabled public String apexClass;
        @AuraEnabled public Decimal priority;
        @AuraEnabled public String recordId;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;

        BacklogRow(Async__c workItem) {
            this.id = workItem.Id;
            this.asyncJobNumber = workItem.Name;
            this.runningUser = workItem.CreatedBy.Name;
            this.apexClass = workItem.Apex__c;
            this.priority = workItem.Priority__c;
            this.recordId = workItem.Record_Id__c;
            this.status = workItem.Status__c;
            this.createdDate = workItem.CreatedDate;
        }
    }
}
