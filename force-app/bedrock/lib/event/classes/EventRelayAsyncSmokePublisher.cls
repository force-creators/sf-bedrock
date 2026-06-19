public with sharing class EventRelayAsyncSmokePublisher extends EventRelay.Publisher {
    public override void execute(List<SObject> records) {
        List<SObject> contacts = new List<SObject>();
        for (SObject record : records) {
            String message = String.valueOf(record.get('Message__c'));
            contacts.add(new Contact(
                LastName = 'EventRelay Async Smoke ' + message,
                Description = 'publisherUser=' + UserInfo.getUserName()
            ));
        }

        DML.insertRecords(contacts);
        Async.enqueue(EventRelayAsyncSmokeJob.class, contacts);
    }
}
