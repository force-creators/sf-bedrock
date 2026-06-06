public virtual inherited sharing class TriggerHandler {
    protected void run() {
        if (!Trigger.isExecuting) return;
        this.stageBuffers();
        this.dispatch();
        this.flushBuffers();
    }

    protected void stageBuffers() {
        RecordBuffer.start();
    }

    protected void flushBuffers() {
        RecordBuffer.flush();
    }

    void dispatch() {
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                this.beforeInsert(this.newRecords());
            }
            when BEFORE_UPDATE {
                this.beforeUpdate(this.newRecords(), this.oldRecordsById());
            }
            when BEFORE_DELETE {
                this.beforeDelete(this.oldRecords(), this.oldRecordsById());
            }
            when AFTER_INSERT {
                this.afterInsert(this.newRecords(), this.newRecordsById());
            }
            when AFTER_UPDATE {
                this.afterUpdate(this.newRecords(), this.oldRecordsById(), this.newRecordsById());
            }
            when AFTER_DELETE {
                this.afterDelete(this.oldRecords(), this.oldRecordsById());
            }
            when AFTER_UNDELETE {
                this.afterUndelete(this.newRecords(), this.newRecordsById());
            }
        }
    }

    System.TriggerOperation operationType() {
        return Trigger.operationType;
    }

    List<SObject> newRecords() {
        return Trigger.new == null ? new List<SObject>() : Trigger.new;
    }

    List<SObject> oldRecords() {
        return Trigger.old == null ? new List<SObject>() : Trigger.old;
    }

    Map<Id, SObject> newRecordsById() {
        return Trigger.newMap == null ? new Map<Id, SObject>() : Trigger.newMap;
    }

    Map<Id, SObject> oldRecordsById() {
        return Trigger.oldMap == null ? new Map<Id, SObject>() : Trigger.oldMap;
    }

    protected virtual void beforeInsert(List<SObject> records) { }
    protected virtual void beforeUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById) { }
    protected virtual void beforeDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById) { }
    protected virtual void afterInsert(List<SObject> records, Map<Id, SObject> recordsById) { }
    protected virtual void afterUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById, Map<Id, SObject> recordsById) { }
    protected virtual void afterDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById) { }
    protected virtual void afterUndelete(List<SObject> records, Map<Id, SObject> recordsById) { }
}
