trigger TormentPingPongEventTrigger on Bedrock_Test_Event__e(after insert) {
    TormentPingPongEventHandler.handle(Trigger.new);
}
