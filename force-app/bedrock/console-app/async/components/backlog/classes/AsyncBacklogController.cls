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
            groupRecord.rows.add(new BacklogRow(workItem));
            groupRecord.status = String.valueOf(groupRecord.rows.size()) + (groupRecord.rows.size() == 1 ? ' job' : ' jobs');
        }

        return groups;
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
