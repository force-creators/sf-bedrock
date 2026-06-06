@istest(testFor='ApexClass:TriggerHandler')
public class TriggerHandlerTest {
    public class Harness extends TriggerHandler {
        Boolean executing = false;
        System.TriggerOperation operation;
        List<SObject> triggerNew = new List<SObject>();
        List<SObject> triggerOld = new List<SObject>();
        Map<Id, SObject> triggerNewMap = new Map<Id, SObject>();
        Map<Id, SObject> triggerOldMap = new Map<Id, SObject>();
        List<String> dispatchCalls = new List<String>();
        Map<String, Integer> recordCountsByHook = new Map<String, Integer>();
        Map<String, Integer> oldMapCountsByHook = new Map<String, Integer>();
        Map<String, Integer> newMapCountsByHook = new Map<String, Integer>();

        void runFromTest() {
            this.run();
        }

        void setContext(
            System.TriggerOperation operation,
            List<SObject> newRecords,
            List<SObject> oldRecords,
            Map<Id, SObject> newRecordsById,
            Map<Id, SObject> oldRecordsById
        ) {
            this.executing = true;
            this.operation = operation;
            this.triggerNew = newRecords == null ? new List<SObject>() : newRecords;
            this.triggerOld = oldRecords == null ? new List<SObject>() : oldRecords;
            this.triggerNewMap = newRecordsById == null ? new Map<Id, SObject>() : newRecordsById;
            this.triggerOldMap = oldRecordsById == null ? new Map<Id, SObject>() : oldRecordsById;
        }

        protected override Boolean isExecuting() {
            return this.executing;
        }

        protected override System.TriggerOperation operationType() {
            return this.operation;
        }

        protected override List<SObject> newRecords() {
            return this.triggerNew;
        }

        protected override List<SObject> oldRecords() {
            return this.triggerOld;
        }

        protected override Map<Id, SObject> newRecordsById() {
            return this.triggerNewMap;
        }

        protected override Map<Id, SObject> oldRecordsById() {
            return this.triggerOldMap;
        }

        void stageBufferedRecord(String hookName) {
            RecordBuffer.put(new Account(Name = hookName));
        }

        protected override void beforeInsert(List<SObject> records) {
            dispatchCalls.add('beforeInsert');
            recordCountsByHook.put('beforeInsert', records.size());
            this.stageBufferedRecord('beforeInsert');
        }

        protected override void beforeUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById) {
            dispatchCalls.add('beforeUpdate');
            recordCountsByHook.put('beforeUpdate', records.size());
            oldMapCountsByHook.put('beforeUpdate', oldRecordsById.size());
            this.stageBufferedRecord('beforeUpdate');
        }

        protected override void beforeDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById) {
            dispatchCalls.add('beforeDelete');
            recordCountsByHook.put('beforeDelete', oldRecords.size());
            oldMapCountsByHook.put('beforeDelete', oldRecordsById.size());
            this.stageBufferedRecord('beforeDelete');
        }

        protected override void afterInsert(List<SObject> records, Map<Id, SObject> recordsById) {
            dispatchCalls.add('afterInsert');
            recordCountsByHook.put('afterInsert', records.size());
            newMapCountsByHook.put('afterInsert', recordsById.size());
            this.stageBufferedRecord('afterInsert');
        }

        protected override void afterUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById, Map<Id, SObject> recordsById) {
            dispatchCalls.add('afterUpdate');
            recordCountsByHook.put('afterUpdate', records.size());
            oldMapCountsByHook.put('afterUpdate', oldRecordsById.size());
            newMapCountsByHook.put('afterUpdate', recordsById.size());
            this.stageBufferedRecord('afterUpdate');
        }

        protected override void afterDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById) {
            dispatchCalls.add('afterDelete');
            recordCountsByHook.put('afterDelete', oldRecords.size());
            oldMapCountsByHook.put('afterDelete', oldRecordsById.size());
            this.stageBufferedRecord('afterDelete');
        }

        protected override void afterUndelete(List<SObject> records, Map<Id, SObject> recordsById) {
            dispatchCalls.add('afterUndelete');
            recordCountsByHook.put('afterUndelete', records.size());
            newMapCountsByHook.put('afterUndelete', recordsById.size());
            this.stageBufferedRecord('afterUndelete');
        }
    }

    static DMLMock setupDmlMock() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        return dmlMock;
    }

    static Account account(String name) {
        return (Account) new TestData(Account.sObjectType)
            .put(Account.Name, name)
            .mockIds()
            .build()[0];
    }

    @istest static void testRunOutsideTriggerNoops() {
        Harness harness = new Harness();

        harness.runFromTest();

        Assert.areEqual(0, harness.dispatchCalls.size(), 'Expected run() to skip dispatch when not in a trigger context.');
    }

    @istest static void testRunDispatchesTriggerOperationsAndFlushesBuffers() {
        DMLMock dmlMock = setupDmlMock();
        Harness harness = new Harness();
        Account newAccount = account('New');
        Account oldAccount = account('Old');
        Map<Id, SObject> newMap = new Map<Id, SObject>{ newAccount.Id => newAccount };
        Map<Id, SObject> oldMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

        harness.setContext(System.TriggerOperation.BEFORE_INSERT, new List<SObject>{ newAccount }, null, null, null);
        harness.runFromTest();
        harness.setContext(System.TriggerOperation.BEFORE_UPDATE, new List<SObject>{ newAccount }, null, null, oldMap);
        harness.runFromTest();
        harness.setContext(System.TriggerOperation.BEFORE_DELETE, null, new List<SObject>{ oldAccount }, null, oldMap);
        harness.runFromTest();
        harness.setContext(System.TriggerOperation.AFTER_INSERT, new List<SObject>{ newAccount }, null, newMap, null);
        harness.runFromTest();
        harness.setContext(System.TriggerOperation.AFTER_UPDATE, new List<SObject>{ newAccount }, null, newMap, oldMap);
        harness.runFromTest();
        harness.setContext(System.TriggerOperation.AFTER_DELETE, null, new List<SObject>{ oldAccount }, null, oldMap);
        harness.runFromTest();
        harness.setContext(System.TriggerOperation.AFTER_UNDELETE, new List<SObject>{ newAccount }, null, newMap, null);
        harness.runFromTest();

        Assert.areEqual(
            new List<String>{ 'beforeInsert', 'beforeUpdate', 'beforeDelete', 'afterInsert', 'afterUpdate', 'afterDelete', 'afterUndelete' },
            harness.dispatchCalls,
            'Expected run() to dispatch each trigger operation to the matching hook.'
        );
        Assert.areEqual(1, harness.recordCountsByHook.get('beforeInsert'), 'Expected beforeInsert tracking to capture one record.');
        Assert.areEqual(1, harness.recordCountsByHook.get('beforeUpdate'), 'Expected beforeUpdate tracking to capture one record.');
        Assert.areEqual(1, harness.oldMapCountsByHook.get('beforeUpdate'), 'Expected beforeUpdate tracking to capture one old-map record.');
        Assert.areEqual(1, harness.recordCountsByHook.get('beforeDelete'), 'Expected beforeDelete tracking to capture one old record.');
        Assert.areEqual(1, harness.oldMapCountsByHook.get('beforeDelete'), 'Expected beforeDelete tracking to capture one old-map record.');
        Assert.areEqual(1, harness.recordCountsByHook.get('afterInsert'), 'Expected afterInsert tracking to capture one record.');
        Assert.areEqual(1, harness.newMapCountsByHook.get('afterInsert'), 'Expected afterInsert tracking to capture one new-map record.');
        Assert.areEqual(1, harness.recordCountsByHook.get('afterUpdate'), 'Expected afterUpdate tracking to capture one record.');
        Assert.areEqual(1, harness.oldMapCountsByHook.get('afterUpdate'), 'Expected afterUpdate tracking to capture one old-map record.');
        Assert.areEqual(1, harness.newMapCountsByHook.get('afterUpdate'), 'Expected afterUpdate tracking to capture one new-map record.');
        Assert.areEqual(1, harness.recordCountsByHook.get('afterDelete'), 'Expected afterDelete tracking to capture one old record.');
        Assert.areEqual(1, harness.oldMapCountsByHook.get('afterDelete'), 'Expected afterDelete tracking to capture one old-map record.');
        Assert.areEqual(1, harness.recordCountsByHook.get('afterUndelete'), 'Expected afterUndelete tracking to capture one record.');
        Assert.areEqual(1, harness.newMapCountsByHook.get('afterUndelete'), 'Expected afterUndelete tracking to capture one new-map record.');
        Assert.areEqual(7, dmlMock.upserts.size(), 'Expected run() to flush buffered records after each dispatched trigger operation.');
    }
}
