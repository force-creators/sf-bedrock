public with sharing class EventRelayIngestSmokeHandler extends EventRelay.Handler {
    public override void execute(List<Generic> records) {
        List<SObject> contacts = new List<SObject>();
        for (Generic record : records) {
            contacts.add(new Contact(
                LastName = 'EventRelay Ingest Smoke ' + record.get('Message__c', String.class),
                Description = 'handlerUser=' + UserInfo.getUserName()
            ));
        }

        DML.insertRecords(contacts);
    }
}
