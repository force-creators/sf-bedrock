@istest
private class EventRelayWakeTriggerTest {
    @istest static void wakeEvent_startsEventRelayPublishPool() {
        ThreadMock mock = new ThreadMock()
            .canEnqueue();
        Thread.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
        Thread__c eventThread = thread(EventRelay.PUBLISH_POOL, 'Bedrock_Test_Event__e');
        insert eventThread;
        mock.queries.pendingThreads.add(eventThread);

        Test.startTest();
        EventBus.publish(new EventRelay_Wake__e());
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(1, mock.service.startCalls,
            'Expected EventRelay wake events to start pending EventRelay publish work.');
        Assert.areEqual(eventThread.Id, mock.service.startedThreads[0],
            'Expected the wake trigger to start the pending EventRelay publish thread.');
    }

    static Thread__c thread(String pool, String threadKey) {
        return new Thread__c(
            Status__c = Thread.PENDING,
            Pool__c = pool,
            Thread_Key__c = threadKey,
            Unique_Key__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(pool + ':' + threadKey)))
        );
    }
}
