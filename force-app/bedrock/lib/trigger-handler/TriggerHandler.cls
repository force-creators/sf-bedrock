/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual inherited sharing class TriggerHandler {
    public void run() {
        if (!this.isExecuting())
            return;
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
        switch on this.operationType() {
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
                this.afterInsert(this.newRecords());
            }
            when AFTER_UPDATE {
                this.afterUpdate(this.newRecords(), this.oldRecordsById());
            }
            when AFTER_DELETE {
                this.afterDelete(this.oldRecords(), this.oldRecordsById());
            }
            when AFTER_UNDELETE {
                this.afterUndelete(this.newRecords());
            }
        }
    }

    protected virtual Boolean isExecuting() {
        return Trigger.isExecuting;
    }

    protected virtual System.TriggerOperation operationType() {
        return Trigger.operationType;
    }

    protected virtual List<SObject> newRecords() {
        return Trigger.new == null ? new List<SObject>() : Trigger.new;
    }

    protected virtual List<SObject> oldRecords() {
        return Trigger.old == null ? new List<SObject>() : Trigger.old;
    }

    protected virtual Map<Id, SObject> newRecordsById() {
        return Trigger.newMap == null ? new Map<Id, SObject>() : Trigger.newMap;
    }

    protected virtual Map<Id, SObject> oldRecordsById() {
        return Trigger.oldMap == null ? new Map<Id, SObject>() : Trigger.oldMap;
    }

    protected virtual void beforeInsert(List<SObject> records) {
    }
    protected virtual void beforeUpdate(
        List<SObject> records,
        Map<Id, SObject> oldMap
    ) {
    }
    protected virtual void beforeDelete(
        List<SObject> oldRecords,
        Map<Id, SObject> oldMap
    ) {
    }
    protected virtual void afterInsert(List<SObject> records) {
    }
    protected virtual void afterUpdate(
        List<SObject> records,
        Map<Id, SObject> oldMap
    ) {
    }
    protected virtual void afterDelete(
        List<SObject> oldRecords,
        Map<Id, SObject> oldMap
    ) {
    }
    protected virtual void afterUndelete(List<SObject> records) {
    }
}
