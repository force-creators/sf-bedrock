public with sharing class EventRelayPublishSmokePublisher extends EventRelay.Publisher {
    public override void execute(List<SObject> records) {
        List<SObject> contacts = new List<SObject>();
        for (SObject record : records) {
            contacts.add(new Contact(
                LastName = 'EventRelay Publish Smoke ' + String.valueOf(record.get('Message__c')),
                Description = 'publisherUser=' + UserInfo.getUserName()
            ));
        }

        DML.insertRecords(contacts);
    }
}
