public without sharing class TormentPingPongEventHandler {
    public static void handle(List<Bedrock_Test_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }

        List<String> messages = new List<String>();
        for (Bedrock_Test_Event__e eventRecord : events) {
            if (
                eventRecord.Message__c != null &&
                eventRecord.Message__c.startsWith('TORMENT|')
            ) {
                messages.add(eventRecord.Message__c);
            }
        }
        if (messages.isEmpty()) {
            return;
        }

        System.enqueueJob(new TormentPingPongQueueable(messages));
    }
}
