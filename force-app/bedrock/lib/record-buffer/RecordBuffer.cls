public inherited sharing class RecordBuffer {
    static List<TriggerContext> contexts = new List<TriggerContext>();

    public static void start() {
        TriggerContext context = new TriggerContext();
        contexts.add(context);
    }

    public static void put(SObject record) {
        currentContext().put(record);
    }

    public static void put(List<SObject> records) {
        currentContext().put(records);
    }

    public static void put(Map<Id, SObject> recordsById) {
        currentContext().put(recordsById);
    }

    public static SObject put(Id recordId) {
        return currentContext().get(recordId);
    }

    public static List<SObject> get(Set<Id> recordIds) {
        return currentContext().get(recordIds);
    }

    public static void flush() {
        if (contexts.isEmpty()) return;

        currentContext().flush();
        contexts.remove(currentContextPosition());
    }

    static TriggerContext currentContext() {
        if (contexts.isEmpty()) start();
        return contexts.get(currentContextPosition());
    }

    static Integer currentContextPosition() {
        return contexts.size() - 1;
    }

    public inherited sharing class TriggerContext {
        public Map<SObjectType, List<SObject>> inserts;
        public Map<SObjectType, Map<Id, SObject>> updates;

        public TriggerContext() {
            this.inserts = new Map<SObjectType, List<SObject>>();
            this.updates = new Map<SObjectType, Map<Id, SObject>>();
        }

        void stageInsert(SObject record) {
            SObjectType sObjectType = record.getSObjectType();
            if (!this.inserts.containsKey(sObjectType))
                this.inserts.put(sObjectType, new List<SObject>());
            this.inserts.get(sObjectType).add(record);
        }

        void stageUpdate(SObject record) {
            SObjectType sObjectType = record.getSObjectType();
            if (!this.updates.containsKey(sObjectType))
                this.updates.put(sObjectType, new Map<Id, SObject>());
            this.updates.get(sObjectType).put(record.Id, record);
        }

        public void put(SObject record) {
            if (record == null) return;
            if (record.Id == null) {
                this.stageInsert(record);
                return;
            }
            this.stageUpdate(record);
        }

        public void put(List<SObject> records) {
            if (records == null) return;
            for (SObject record : records) 
                this.put(record);
        }

        public void put(Map<Id, SObject> recordsById) {
            if (recordsById == null) return;
            this.put(recordsById.values());
        }

        public SObject get(Id recordId) {
            if (recordId == null) return null;

            SObjectType sObjectType = recordId.getSObjectType();
            Map<Id, SObject> recordsById = this.updates.get(sObjectType);
            if (recordsById == null)
                return sObjectType.newSObject(recordId);
            if (!recordsById.containsKey(recordId)) 
                return sObjectType.newSObject(recordId);

            return recordsById.get(recordId);
        }

        public List<SObject> get(Set<Id> recordIds) {
            if (recordIds == null || recordIds.isEmpty()) return null;

            List<SObject> results = new List<SObject>();            
            for (Id recordId : recordIds)
                results.add(this.get(recordId));

            return results;
        }

        public void flush() {
            Map<SObjectType, List<SObject>> upserts = new Map<SObjectType, List<SObject>>();
            
            for(SObjectType sObjectType : this.inserts.keySet()) {
                List<SObject> records = this.inserts.get(sObjectType);
                if(!upserts.containsKey(sObjectType)) 
                    upserts.put(sObjectType, new List<SObject>());
                upserts.get(sObjectType).addAll(records);
            }

            for(SObjectType sObjectType : this.updates.keySet()) {
                Map<Id, SObject> recordsById = this.updates.get(sObjectType);
                if(!upserts.containsKey(sObjectType)) 
                    upserts.put(sObjectType, new List<SObject>());
                upserts.get(sObjectType).addAll(recordsById.values());
            }

            for(SObjectType sObjectType : upserts.keySet()) {
                List<SObject> records = upserts.get(sObjectType);
                DML.upsertRecords(records);
            }
        }
    }
    public class RecordBufferException extends Exception { }
}