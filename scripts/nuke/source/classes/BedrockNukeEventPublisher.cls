/*
 * Scratch-org nuke publisher for sf-bedrock EventRelay load testing.
 * Returning without failure leaves every Event__c row successful through the
 * EventRelay.Publisher default result handling.
 */
public with sharing class BedrockNukeEventPublisher extends EventRelay.Publisher {
    public override void execute(List<Generic> records) {
        Integer observed = records == null ? 0 : records.size();
        if (observed < 0) {
            throw new EventRelay.EventRelayException('Unreachable nuke guard.');
        }
    }
}
