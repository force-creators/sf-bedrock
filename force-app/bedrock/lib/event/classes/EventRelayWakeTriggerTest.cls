@istest
class EventRelayWakeTriggerTest {
    @istest static void wakeEvent_startsEventRelayPublishPool() {
        ThreadMock mock = new ThreadMock()
            .canEnqueue();
        Thread.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
        Thread__c eventThread = thread(EventRelay.consts.PUBLISH_POOL, 'Bedrock_Test_Event__e');
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

    @istest static void wakeEvent_startsEventRelayProcessPool() {
        ThreadMock mock = new ThreadMock()
            .canEnqueue();
        Thread.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
        Thread__c processThread = thread(EventRelay.consts.PROCESS_POOL, 'Bedrock_Test_Event__e');
        insert processThread;
        mock.queries.pendingThreadsByPool.put(
            EventRelay.consts.PROCESS_POOL,
            new List<Thread__c> { processThread }
        );

        Test.startTest();
        EventBus.publish(new EventRelay_Wake__e());
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(1, mock.service.startCalls,
            'Expected EventRelay wake events to start pending EventRelay process work.');
        Assert.areEqual(processThread.Id, mock.service.startedThreads[0],
            'Expected the wake trigger to start the pending EventRelay process thread.');
    }

    @istest static void wakeEvent_startsPublishAndProcessPools() {
        ThreadMock mock = new ThreadMock()
            .canEnqueue();
        Thread.setMock(mock);
        Thread.settings.setSettings(new Thread_Settings__c(Max_Threads__c = 2));
        Thread__c publishThread = thread(EventRelay.consts.PUBLISH_POOL, 'publish');
        Thread__c processThread = thread(EventRelay.consts.PROCESS_POOL, 'process');
        insert new List<Thread__c> { publishThread, processThread };
        mock.queries.pendingThreadsByPool.put(
            EventRelay.consts.PUBLISH_POOL,
            new List<Thread__c> { publishThread }
        );
        mock.queries.pendingThreadsByPool.put(
            EventRelay.consts.PROCESS_POOL,
            new List<Thread__c> { processThread }
        );

        Test.startTest();
        EventBus.publish(new EventRelay_Wake__e());
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(2, mock.service.startCalls,
            'Expected one wake event to fill available EventRelay publish and process slots.');
        Assert.areEqual(new Set<Id> { publishThread.Id, processThread.Id }, new Set<Id>(mock.service.startedThreads),
            'Expected the wake trigger to start pending work from both EventRelay pools.');
    }

    static Thread__c thread(String pool, String threadKey) {
        return new Thread__c(
            Status__c = Thread.consts.PENDING,
            Pool__c = pool,
            Thread_Key__c = threadKey,
            Unique_Key__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(pool + ':' + threadKey)))
        );
    }
}
