public with sharing class AsyncCompletedController {
    static final Integer MAX_ROWS = 500;
    static final Set<String> SORT_FIELDS = new Set<String>{
        'asyncJobNumber',
        'apexClass',
        'recordId',
        'thread',
        'createdDate'
    };

    @AuraEnabled(cacheable=true)
    public static List<CompletedRow> getCompleted(String searchTerm, String sortBy, String sortDirection) {
        String normalizedSearchTerm = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
        String orderByField = sortField(sortBy);
        String orderByDirection = sortOrder(sortDirection);

        List<CompletedRow> rows = new List<CompletedRow>();
        for (Async__c workItem : [
            SELECT Id, Name, Apex__c, Record_Id__c, Thread__c, CreatedDate
            FROM Async__c
            WHERE Status__c = 'Done'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            CompletedRow row = new CompletedRow(workItem);
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
            'thread' => 'Thread__c',
            'createdDate' => 'CreatedDate'
        };
        return fieldByName.get(sortBy);
    }

    static String sortOrder(String sortDirection) {
        return String.isBlank(sortDirection) ? 'DESC' : (sortDirection.toLowerCase() == 'asc' ? 'ASC' : 'DESC');
    }

    static Boolean matchesFilter(CompletedRow row, String searchTerm) {
        if (searchTerm == null) {
            return true;
        }

        return containsIgnoreCase(row.asyncJobNumber, searchTerm) ||
            containsIgnoreCase(row.apexClass, searchTerm) ||
            containsIgnoreCase(row.recordId, searchTerm) ||
            containsIgnoreCase(row.thread, searchTerm);
    }

    static Boolean containsIgnoreCase(String value, String searchTerm) {
        return value != null && value.toLowerCase().contains(searchTerm);
    }

    public class CompletedRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String asyncJobNumber;
        @AuraEnabled public String apexClass;
        @AuraEnabled public String recordId;
        @AuraEnabled public String thread;
        @AuraEnabled public Datetime createdDate;

        CompletedRow(Async__c workItem) {
            this.id = workItem.Id;
            this.asyncJobNumber = workItem.Name;
            this.apexClass = workItem.Apex__c;
            this.recordId = workItem.Record_Id__c;
            this.thread = workItem.Thread__c;
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

            if (this.sortBy == 'asyncJobNumber') {
                result = compareStrings(left.asyncJobNumber, right.asyncJobNumber);
            } else if (this.sortBy == 'Apex__c') {
                result = compareStrings(left.apexClass, right.apexClass);
            } else if (this.sortBy == 'Record_Id__c') {
                result = compareStrings(left.recordId, right.recordId);
            } else if (this.sortBy == 'Thread__c') {
                result = compareStrings(left.thread, right.thread);
            } else {
                result = compareDatetimes(left.createdDate, right.createdDate);
            }

            return this.sortDirection == 'ASC' ? result : -result;
        }

        Integer compareStrings(String left, String right) {
            if (left == right) return 0;
            if (left == null) return -1;
            if (right == null) return 1;
            return left.toLowerCase().compareTo(right.toLowerCase());
        }

        Integer compareDatetimes(Datetime left, Datetime right) {
            if (left == right) return 0;
            if (left == null) return -1;
            if (right == null) return 1;
            Long leftTime = left.getTime();
            Long rightTime = right.getTime();
            if (leftTime == rightTime) return 0;
            return leftTime > rightTime ? 1 : -1;
        }
    }
}
