public with sharing class AsyncCompletedController {
    static final Integer MAX_ROWS = 500;
    static final Set<String> SORT_FIELDS = new Set<String>{
        'asyncJobNumber',
        'apexClass',
        'recordId',
        'thread',
        'createdDate'
    };

    @AuraEnabled
    public static List<CompletedRow> getCompleted(String searchTerm, String sortBy, String sortDirection) {
        String normalizedSearchTerm = BedrockConsoleSupport.normalizeSearchTerm(searchTerm);
        String orderByField = sortField(sortBy);
        String orderByDirection = BedrockConsoleSupport.sortOrder(sortDirection);

        List<CompletedRow> rows = new List<CompletedRow>();
        List<Async__c> workItems = Database.query(
            'SELECT Id, Name, Apex__c, Record_Id__c, Thread__c, CreatedDate ' +
            'FROM Async__c ' +
            'WHERE Status__c = \'Done\' ' +
            'WITH USER_MODE ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT 500'
        );
        Map<Id, Thread__c> threadsById = BedrockConsoleSupport.asyncThreadsById(workItems);

        for (Async__c workItem : workItems) {
            CompletedRow row = new CompletedRow(workItem, threadsById);
            if (matchesFilter(row, normalizedSearchTerm)) {
                rows.add(row);
            }
        }

        rows.sort(new CompletedRowSorter(orderByField, orderByDirection));
        return rows;
    }

    static String sortField(String sortBy) {
        if (!SORT_FIELDS.contains(sortBy)) {
            return 'createdDate';
        }

        Map<String, String> fieldByName = new Map<String, String>{
            'asyncJobNumber' => 'asyncJobNumber',
            'apexClass' => 'Apex__c',
            'recordId' => 'Record_Id__c',
            'thread' => 'thread',
            'createdDate' => 'CreatedDate'
        };
        return fieldByName.get(sortBy);
    }

    static Boolean matchesFilter(CompletedRow row, String searchTerm) {
        if (searchTerm == null) {
            return true;
        }

        return BedrockConsoleSupport.containsIgnoreCase(row.asyncJobNumber, searchTerm) ||
            BedrockConsoleSupport.containsIgnoreCase(row.apexClass, searchTerm) ||
            BedrockConsoleSupport.containsIgnoreCase(row.recordId, searchTerm) ||
            BedrockConsoleSupport.containsIgnoreCase(row.thread, searchTerm);
    }

    static String threadLabel(Async__c workItem, Map<Id, Thread__c> threadsById) {
        return BedrockConsoleSupport.asyncThreadLabel(workItem, threadsById, null);
    }

    public class CompletedRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String asyncJobNumber;
        @AuraEnabled public String apexClass;
        @AuraEnabled public String recordId;
        @AuraEnabled public String thread;
        @AuraEnabled public Datetime createdDate;

        CompletedRow(Async__c workItem, Map<Id, Thread__c> threadsById) {
            this.id = workItem.Id;
            this.asyncJobNumber = workItem.Name;
            this.apexClass = workItem.Apex__c;
            this.recordId = workItem.Record_Id__c;
            this.thread = threadLabel(workItem, threadsById);
            this.createdDate = workItem.CreatedDate;
        }
    }

    class CompletedRowSorter implements Comparator<CompletedRow> {
        String sortBy;
        String sortDirection;

        CompletedRowSorter(String sortBy, String sortDirection) {
            this.sortBy = sortBy;
            this.sortDirection = sortDirection;
        }

        public Integer compare(CompletedRow left, CompletedRow right) {
            Integer result;

            result = BedrockConsoleSupport.compareValues(valueOf(left, this.sortBy), valueOf(right, this.sortBy));

            return this.sortDirection == 'ASC' ? result : -result;
        }

        Object valueOf(CompletedRow row, String fieldName) {
            if (fieldName == 'asyncJobNumber') return row.asyncJobNumber;
            if (fieldName == 'Apex__c') return row.apexClass;
            if (fieldName == 'Record_Id__c') return row.recordId;
            if (fieldName == 'thread') return row.thread;
            return row.createdDate;
        }
    }
}
