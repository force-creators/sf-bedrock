/*
 * Scratch-org nuke subscriber for sf-bedrock load testing.
 * This class intentionally performs no record DML; the framework finalizer
 * marks Async__c rows complete after execute(Set<Id>) returns successfully.
 */
public with sharing class BedrockNukeAsync extends Async {
    public override void execute(Set<Id> ids) {
        Integer observed = ids == null ? 0 : ids.size();
        if (observed < 0) {
            throw new Async.AsyncException('Unreachable nuke guard.');
        }
    }
}
