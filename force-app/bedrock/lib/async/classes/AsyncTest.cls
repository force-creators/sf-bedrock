@istest(testFor='ApexClass:Async')
public with sharing class AsyncTest {
    
    @istest static void testAsync() {
        List<Contact> contacts = new List<Contact> {
            new Contact(LastName = 'Test1'),
            new Contact(LastName = 'Test2'),
            new Contact(LastName = 'Test3'),
            new Contact(LastName = 'Test4')
        };
        insert contacts;

        Test.startTest();
            AsyncOptions options = new AsyncOptions();
            options.maximumQueueableStackDepth = 5;
            Async.jobs.hasEnqueued = true;
            Async.enqueue(MyTestAsync.class, contacts);
            System.enqueueJob(new AsyncThread(Async.jobs.threadId), options);
        Test.stopTest();

        for(Contact contact : [SELECT Id, FirstName FROM Contact]) {
            System.assertEquals('Hello', contact.FirstName);
        }

        for(Async__c workItem : [SELECT Id, Status__c FROM Async__c]) {
            System.assertEquals('Done', workItem.Status__c);
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
}
