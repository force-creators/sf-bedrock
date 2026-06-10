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
            System.assertEquals('Done', workItem.Status__c);
        }

        for(Contact contact : [SELECT Id, FirstName FROM Contact]) {
            System.assertEquals('Hello', contact.FirstName);
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
