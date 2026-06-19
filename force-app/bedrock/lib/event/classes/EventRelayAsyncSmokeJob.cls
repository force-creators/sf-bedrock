public with sharing class EventRelayAsyncSmokeJob extends Async {
    public override void execute(Set<Id> ids) {
        List<Contact> contacts = (List<Contact>) Query.records([
            SELECT Id, Description
            FROM Contact
            WHERE Id IN :ids
        ]);

        for (Contact contact : contacts) {
            contact.Description = contact.Description
                + '; asyncJobUser=' + UserInfo.getUserName()
                + '; asyncCompleted=' + String.valueOf(System.now());
        }

        DML.updateRecords(contacts);
    }
}
