public with sharing class AsyncArchiveController {
    static final Integer MAX_ROWS = 500;
    static final Set<String> ACTIVE_BATCH_STATUSES = new Set<String>{ 'Holding', 'Queued', 'Preparing', 'Processing' };
    static final Set<String> SORT_FIELDS = new Set<String>{
        'archiveNumber',
        'apexClass',
        'recordId',
        'thread',
        'createdDate'
    };

    @AuraEnabled
    public static List<ArchiveRow> getArchives(String searchTerm, String sortBy, String sortDirection) {
        String normalizedSearchTerm = String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
        String orderByField = sortField(sortBy);
        String orderByDirection = sortOrder(sortDirection);

        List<ArchiveRow> rows = new List<ArchiveRow>();
        List<Async_Archive__c> archives = Database.query(
            'SELECT Id, Name, Apex__c, Record_Id__c, Thread__c, CreatedDate ' +
            'FROM Async_Archive__c ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT 500'
        );

        for (Async_Archive__c archive : archives) {
            ArchiveRow row = new ArchiveRow(archive);
            if (matchesFilter(row, normalizedSearchTerm)) {
                rows.add(row);
            }
        }

        rows.sort(new ArchiveRowSorter(orderByField, orderByDirection));
        return rows;
    }

    @AuraEnabled
    public static Boolean isArchiveRunning() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'AsyncArchiveBatch'
                AND Status IN :ACTIVE_BATCH_STATUSES
                AND JobType = 'BatchApex'
        ] > 0;
    }

    @AuraEnabled
    public static Id runNow() {
        return AsyncArchiveJob.runNow();
    }

    static String sortField(String sortBy) {
        if (!SORT_FIELDS.contains(sortBy)) {
            return 'createdDate';
        }

        Map<String, String> fieldByName = new Map<String, String>{
            'archiveNumber' => 'archiveNumber',
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

    static Boolean matchesFilter(ArchiveRow row, String searchTerm) {
        if (searchTerm == null) {
            return true;
        }

        return containsIgnoreCase(row.archiveNumber, searchTerm) ||
            containsIgnoreCase(row.apexClass, searchTerm) ||
            containsIgnoreCase(row.recordId, searchTerm) ||
            containsIgnoreCase(row.thread, searchTerm);
    }

    static Boolean containsIgnoreCase(String value, String searchTerm) {
        return value != null && value.toLowerCase().contains(searchTerm);
    }

    public class ArchiveRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String archiveNumber;
        @AuraEnabled public String apexClass;
        @AuraEnabled public String recordId;
        @AuraEnabled public String thread;
        @AuraEnabled public Datetime createdDate;

        ArchiveRow(Async_Archive__c archive) {
            this.id = archive.Id;
            this.archiveNumber = archive.Name;
            this.apexClass = archive.Apex__c;
            this.recordId = archive.Record_Id__c;
            this.thread = archive.Thread__c;
            this.createdDate = archive.CreatedDate;
        }
    }

    class ArchiveRowSorter implements Comparator<ArchiveRow> {
        String sortBy;
        String sortDirection;

        ArchiveRowSorter(String sortBy, String sortDirection) {
            this.sortBy = sortBy;
            this.sortDirection = sortDirection;
        }

        public Integer compare(ArchiveRow left, ArchiveRow right) {
            Object leftValue = valueOf(left, sortBy);
            Object rightValue = valueOf(right, sortBy);
            Integer result = compareValues(leftValue, rightValue);
            return sortDirection == 'ASC' ? result : -result;
        }

        Object valueOf(ArchiveRow row, String fieldName) {
            if (fieldName == 'archiveNumber') return row.archiveNumber;
            if (fieldName == 'Apex__c') return row.apexClass;
            if (fieldName == 'Record_Id__c') return row.recordId;
            if (fieldName == 'Thread__c') return row.thread;
            return row.createdDate;
        }

        Integer compareValues(Object leftValue, Object rightValue) {
            if (leftValue == rightValue) return 0;
            if (leftValue == null) return -1;
            if (rightValue == null) return 1;
            if (leftValue instanceof Datetime) {
                Long leftTime = ((Datetime) leftValue).getTime();
                Long rightTime = ((Datetime) rightValue).getTime();
                if (leftTime == rightTime) return 0;
                return leftTime < rightTime ? -1 : 1;
            }
            return String.valueOf(leftValue).toLowerCase().compareTo(String.valueOf(rightValue).toLowerCase());
        }
    }
}
