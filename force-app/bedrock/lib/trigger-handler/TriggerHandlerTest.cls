@istest(testFor='ApexClass:TriggerHandler')
private class TriggerHandlerTest {
    private class Harness extends TriggerHandler {
        List<String> dispatchCalls = new List<String>();
        Map<String, Integer> recordCountsByHook = new Map<String, Integer>();
        Map<String, Integer> oldMapCountsByHook = new Map<String, Integer>();
        Map<String, Integer> newMapCountsByHook = new Map<String, Integer>();

        void runFromTest() {
            this.run();
        }

        void invokeBeforeInsert(List<SObject> records) {
            this.beforeInsert(records);
        }

        void invokeBeforeUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById) {
            this.beforeUpdate(records, oldRecordsById);
        }

        void invokeAfterInsert(List<SObject> records, Map<Id, SObject> recordsById) {
            this.afterInsert(records, recordsById);
        }

        protected override void beforeInsert(List<SObject> records) {
            dispatchCalls.add('beforeInsert');
            recordCountsByHook.put('beforeInsert', records.size());
        }

        protected override void beforeUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById) {
            dispatchCalls.add('beforeUpdate');
            recordCountsByHook.put('beforeUpdate', records.size());
            oldMapCountsByHook.put('beforeUpdate', oldRecordsById.size());
        }

        protected override void beforeDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById) {
            dispatchCalls.add('beforeDelete');
            recordCountsByHook.put('beforeDelete', oldRecords.size());
            oldMapCountsByHook.put('beforeDelete', oldRecordsById.size());
        }

        protected override void afterInsert(List<SObject> records, Map<Id, SObject> recordsById) {
            dispatchCalls.add('afterInsert');
            recordCountsByHook.put('afterInsert', records.size());
            newMapCountsByHook.put('afterInsert', recordsById.size());
        }

        protected override void afterUpdate(List<SObject> records, Map<Id, SObject> oldRecordsById, Map<Id, SObject> recordsById) {
            dispatchCalls.add('afterUpdate');
            recordCountsByHook.put('afterUpdate', records.size());
            oldMapCountsByHook.put('afterUpdate', oldRecordsById.size());
            newMapCountsByHook.put('afterUpdate', recordsById.size());
        }

        protected override void afterDelete(List<SObject> oldRecords, Map<Id, SObject> oldRecordsById) {
            dispatchCalls.add('afterDelete');
            recordCountsByHook.put('afterDelete', oldRecords.size());
            oldMapCountsByHook.put('afterDelete', oldRecordsById.size());
        }

        protected override void afterUndelete(List<SObject> records, Map<Id, SObject> recordsById) {
            dispatchCalls.add('afterUndelete');
            recordCountsByHook.put('afterUndelete', records.size());
            newMapCountsByHook.put('afterUndelete', recordsById.size());
        }
    }

    @istest static void testRunOutsideTriggerNoops() {
        Harness harness = new Harness();

        harness.runFromTest();

        Assert.areEqual(0, harness.dispatchCalls.size(), 'Expected run() to skip dispatch when not in a trigger context.');
    }

    @istest static void testHarnessHookTracking() {
        Harness harness = new Harness();
        Account account = new Account(Name = 'Harness');
        Account oldAccount = new Account(Id = Id.valueOf('001000000000001AAA'), Name = 'Old');
        Map<Id, SObject> oldMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };
        Map<Id, SObject> newMap = new Map<Id, SObject>{ oldAccount.Id => account };

        harness.invokeBeforeInsert(new List<SObject>{ account });
        harness.invokeBeforeUpdate(new List<SObject>{ account }, oldMap);
        harness.invokeAfterInsert(new List<SObject>{ account }, newMap);

        Assert.areEqual(new List<String>{ 'beforeInsert', 'beforeUpdate', 'afterInsert' }, harness.dispatchCalls, 'Expected harness hook wrappers to record invoked hooks in order.');
        Assert.areEqual(1, harness.recordCountsByHook.get('beforeInsert'), 'Expected beforeInsert tracking to capture one record.');
        Assert.areEqual(1, harness.recordCountsByHook.get('beforeUpdate'), 'Expected beforeUpdate tracking to capture one record.');
        Assert.areEqual(1, harness.oldMapCountsByHook.get('beforeUpdate'), 'Expected beforeUpdate tracking to capture one old-map record.');
        Assert.areEqual(1, harness.recordCountsByHook.get('afterInsert'), 'Expected afterInsert tracking to capture one record.');
        Assert.areEqual(1, harness.newMapCountsByHook.get('afterInsert'), 'Expected afterInsert tracking to capture one new-map record.');
    }
}
