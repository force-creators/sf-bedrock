@istest(testFor='ApexClass:Async')
public with sharing class AsyncTest {
    
    @istest static void testMock() {

        List<Contact> contacts = new List<Contact> {
            new Contact(LastName = 'Test1'),
            new Contact(LastName = 'Test2'),
            new Contact(LastName = 'Test3'),
            new Contact(LastName = 'Test4')
        };
        insert contacts;


        AsyncMock mock = new AsyncMock().canEnqueue();
        Async.setMock(mock);

        Test.startTest();
            Async.enqueue(MyTestAsync.class, contacts);
        Test.stopTest();

        for(Async__c workItem : [SELECT Id, Status__c FROM Async__c]) {
            Assert.areEqual('Done', workItem.Status__c, 'Expected all async work items to be marked done after the queueable chain finishes.');
        }

        for(Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual('Hello', contact.FirstName, 'Expected the async job to update each staged contact.');
        }
    }

    @istest static void testEnqueueFromAsync_defersChildWorkUntilFinalizer() {
        List<Contact> contacts = new List<Contact> {
            new Contact(LastName = 'Setup Safe 1'),
            new Contact(LastName = 'Setup Safe 2')
        };
        insert contacts;

        AsyncMock mock = new AsyncMock().canEnqueue();
        Async.setMock(mock);

        Test.startTest();
            Async.enqueue(SetupSafeParentAsync.class, contacts);
        Test.stopTest();

        Map<String, Integer> workItemsByApex = new Map<String, Integer>();
        for (Async__c workItem : [SELECT Apex__c, Status__c FROM Async__c]) {
            Assert.areEqual('Done', workItem.Status__c, 'Expected parent and child work items to finish successfully.');
            if (!workItemsByApex.containsKey(workItem.Apex__c)) {
                workItemsByApex.put(workItem.Apex__c, 0);
            }
            workItemsByApex.put(workItem.Apex__c, workItemsByApex.get(workItem.Apex__c) + 1);
        }

        Assert.areEqual(2, workItemsByApex.get(String.valueOf(SetupSafeParentAsync.class)), 'Expected one parent work item for each contact.');
        Assert.areEqual(2, workItemsByApex.get(String.valueOf(SetupSafeChildAsync.class)), 'Expected child work to be created from the finalizer after setup DML.');

        for(Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual('Child', contact.FirstName, 'Expected child async work to run after parent setup-object DML succeeds.');
        }
    }

    @istest static void testStageAndFlush_createsWorkInSingleDmlTransaction() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        List<SObject> contacts = new TestData(Contact.sObjectType)
            .mockIds()
            .count(2)
            .build();
        Set<Id> contactIds = Pluck.ids(contacts);

        Async.stage(MyTestAsync.class, new Set<Id> { contacts[0].Id });
        Async.stage(MyTestAsync.class, contactIds);
        Async.stage(SetupSafeChildAsync.class, contactIds);
        Async.flush();

        Assert.areEqual(1, dmlMock.inserts.size(), 'Expected flush() to create all staged work in one DML insert call.');
        Assert.areEqual(4, dmlMock.inserts[0].size(), 'Expected flush() to merge duplicate staged ids by Apex class before creating work items.');
    }

    @istest static void testStageAndFlushFromAsync_defersChildWorkUntilFinalizer() {
        List<Contact> contacts = new List<Contact> {
            new Contact(LastName = 'Staged Setup Safe 1'),
            new Contact(LastName = 'Staged Setup Safe 2')
        };
        insert contacts;

        AsyncMock mock = new AsyncMock().canEnqueue();
        Async.setMock(mock);

        Test.startTest();
            Async.enqueue(SetupSafeStagedParentAsync.class, contacts);
        Test.stopTest();

        Map<String, Integer> workItemsByApex = new Map<String, Integer>();
        for (Async__c workItem : [SELECT Apex__c, Status__c FROM Async__c]) {
            Assert.areEqual('Done', workItem.Status__c, 'Expected staged parent and child work items to finish successfully.');
            if (!workItemsByApex.containsKey(workItem.Apex__c)) {
                workItemsByApex.put(workItem.Apex__c, 0);
            }
            workItemsByApex.put(workItem.Apex__c, workItemsByApex.get(workItem.Apex__c) + 1);
        }

        Assert.areEqual(2, workItemsByApex.get(String.valueOf(SetupSafeStagedParentAsync.class)), 'Expected one staged parent work item for each contact.');
        Assert.areEqual(2, workItemsByApex.get(String.valueOf(SetupSafeChildAsync.class)), 'Expected staged child work to be created from the finalizer after setup DML.');

        for(Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual('Child', contact.FirstName, 'Expected staged child async work to run after parent setup-object DML succeeds.');
        }
    }

    public with sharing class MyTestAsync extends Async {
        public override void execute(Set<Id> ids) {
            List<Contact> contacts = [SELECT Id, FirstName, LastName FROM Contact WHERE Id IN :ids];
            for(Contact contact : contacts) {
                contact.FirstName = 'Hello';
            }
            update contacts;
        }
    }

    public with sharing class SetupSafeParentAsync extends Async {
        public override void execute(Set<Id> ids) {
            String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '0');
            DML.insertRecords(new List<SObject> {
                new Group(
                    Name = 'Async Setup Safe ' + suffix,
                    DeveloperName = 'Async_Setup_Safe_' + suffix,
                    Type = 'Regular'
                )
            });

            Async.enqueue(SetupSafeChildAsync.class, ids);
            Async.enqueue(SetupSafeChildAsync.class, ids);
        }
    }

    public with sharing class SetupSafeStagedParentAsync extends Async {
        public override void execute(Set<Id> ids) {
            String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '0');
            DML.insertRecords(new List<SObject> {
                new Group(
                    Name = 'Async Staged Setup Safe ' + suffix,
                    DeveloperName = 'Async_Staged_Setup_Safe_' + suffix,
                    Type = 'Regular'
                )
            });

            Async.stage(SetupSafeChildAsync.class, ids);
            Async.stage(SetupSafeChildAsync.class, ids);
            Async.flush();
        }
    }

    public with sharing class SetupSafeChildAsync extends Async {
        public override void execute(Set<Id> ids) {
            List<Contact> contacts = [SELECT Id, FirstName FROM Contact WHERE Id IN :ids];
            for(Contact contact : contacts) {
                contact.FirstName = 'Child';
            }
            update contacts;
        }
    }
}
