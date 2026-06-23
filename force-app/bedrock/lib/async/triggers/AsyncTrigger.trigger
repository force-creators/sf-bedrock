trigger AsyncTrigger on Async__c(
    before insert,
    after insert,
    before update,
    after update,
    before delete,
    after delete
) {
    new AsyncTriggerHandler().run();
}
