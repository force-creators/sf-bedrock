@istest(testFor='ApexClass:Async')
public with sharing class AsyncTest {
    
    @istest static void testMock() {

        List<Contact> contacts = new List<Contact> {
            new Contact(LastName = 'Test1'),
            new Contact(LastName = 'Test2'),
            new Contact(LastName = 'Test3'),
            new Contact(LastName = 'Test4')
        };
        insert contacts;


        AsyncMock mock = new AsyncMock().canEnqueue();
        Async.setMock(mock);

        Test.startTest();
            Async.enqueue(MyTestAsync.class, contacts);
        Test.stopTest();

        for(Async__c workItem : [SELECT Id, Status__c FROM Async__c]) {
            Assert.areEqual('Done', workItem.Status__c, 'Expected all async work items to be marked done after the queueable chain finishes.');
        }

        for(Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual('Hello', contact.FirstName, 'Expected the async job to update each staged contact.');
        }
    }

    @istest static void testEnqueueFromAsync_defersChildWorkUntilFinalizer() {
        List<Contact> contacts = new List<Contact> {
            new Contact(LastName = 'Setup Safe 1'),
            new Contact(LastName = 'Setup Safe 2')
        };
        insert contacts;

        AsyncMock mock = new AsyncMock().canEnqueue();
        Async.setMock(mock);

        Test.startTest();
            Async.enqueue(SetupSafeParentAsync.class, contacts);
        Test.stopTest();

        Map<String, Integer> workItemsByApex = new Map<String, Integer>();
        for (Async__c workItem : [SELECT Apex__c, Status__c FROM Async__c]) {
            Assert.areEqual('Done', workItem.Status__c, 'Expected parent and child work items to finish successfully.');
            if (!workItemsByApex.containsKey(workItem.Apex__c)) {
                workItemsByApex.put(workItem.Apex__c, 0);
            }
            workItemsByApex.put(workItem.Apex__c, workItemsByApex.get(workItem.Apex__c) + 1);
        }

        Assert.areEqual(2, workItemsByApex.get(String.valueOf(SetupSafeParentAsync.class)), 'Expected one parent work item for each contact.');
        Assert.areEqual(2, workItemsByApex.get(String.valueOf(SetupSafeChildAsync.class)), 'Expected child work to be created from the finalizer after setup DML.');

        for(Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual('Child', contact.FirstName, 'Expected child async work to run after parent setup-object DML succeeds.');
        }
    }

    @istest static void testStageAndFlush_createsWorkInSingleDmlTransaction() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        List<SObject> contacts = new TestData(Contact.sObjectType)
            .mockIds()
            .count(2)
            .build();
        Set<Id> contactIds = Pluck.ids(contacts);

        Async.stage(MyTestAsync.class, new Set<Id> { contacts[0].Id });
        Async.stage(MyTestAsync.class, contactIds);
        Async.stage(SetupSafeChildAsync.class, contactIds);
        Async.flush();

        Assert.areEqual(1, dmlMock.inserts.size(), 'Expected flush() to create all staged work in one DML insert call.');
        Assert.areEqual(4, dmlMock.inserts[0].size(), 'Expected flush() to merge duplicate staged ids by Apex class before creating work items.');
    }

    @istest static void testStageAndFlushFromAsync_defersChildWorkUntilFinalizer() {
        List<Contact> contacts = new List<Contact> {
            new Contact(LastName = 'Staged Setup Safe 1'),
            new Contact(LastName = 'Staged Setup Safe 2')
        };
        insert contacts;

        AsyncMock mock = new AsyncMock().canEnqueue();
        Async.setMock(mock);

        Test.startTest();
            Async.enqueue(SetupSafeStagedParentAsync.class, contacts);
        Test.stopTest();

        Map<String, Integer> workItemsByApex = new Map<String, Integer>();
        for (Async__c workItem : [SELECT Apex__c, Status__c FROM Async__c]) {
            Assert.areEqual('Done', workItem.Status__c, 'Expected staged parent and child work items to finish successfully.');
            if (!workItemsByApex.containsKey(workItem.Apex__c)) {
                workItemsByApex.put(workItem.Apex__c, 0);
            }
            workItemsByApex.put(workItem.Apex__c, workItemsByApex.get(workItem.Apex__c) + 1);
        }

        Assert.areEqual(2, workItemsByApex.get(String.valueOf(SetupSafeStagedParentAsync.class)), 'Expected one staged parent work item for each contact.');
        Assert.areEqual(2, workItemsByApex.get(String.valueOf(SetupSafeChildAsync.class)), 'Expected staged child work to be created from the finalizer after setup DML.');

        for(Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual('Child', contact.FirstName, 'Expected staged child async work to run after parent setup-object DML succeeds.');
        }
    }

    @istest static void testMetadataService_cachesConfigReadsForSameJobType() {
        CountingMetadataService metadata = new CountingMetadataService();

        metadata.getConfig('Some_Async_Class');
        metadata.getConfig('Some_Async_Class');
        metadata.getConfig('Some_Async_Class');

        Assert.areEqual(1, metadata.loadCount, 'Expected repeated config reads for the same job type to load once and serve the transaction cache.');

        metadata.getConfig('Another_Async_Class');

        Assert.areEqual(2, metadata.loadCount, 'Expected a distinct job type to trigger one additional load.');
    }

    @istest static void testMetadataService_fallsBackToDefaultWhenNoConfigRow() {
        Async_Config__mdt config = new Async.MetadataService().getConfig('No_Such_Async_Config_Row');

        Assert.areEqual(5, config.Batch_Size__c, 'Expected the default batch size when no Async_Config__mdt row exists for the job type.');
        Assert.areEqual(null, config.Max_Retries__c, 'Expected no Max_Retries__c on the default config so auto-retry stays off.');
        Assert.areEqual(0, config.Priority__c, 'Expected the default priority to seed work items at the lowest priority when no config row exists.');
    }

    @istest static void testCreate_seedsConfiguredPriorityOnWorkItems() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Async.setMock(new AsyncMock().config(MyPriorityAsync.class, new Async_Config__mdt(Priority__c = 42)));

        List<SObject> contacts = new TestData(Contact.sObjectType)
            .mockIds()
            .count(2)
            .build();

        Async.enqueue(MyPriorityAsync.class, Pluck.ids(contacts));

        Assert.areEqual(1, dmlMock.inserts.size(), 'Expected one insert batch when enqueuing seeded work items.');
        for (Async__c workItem : (List<Async__c>) dmlMock.inserts[0]) {
            Assert.areEqual(42, workItem.Priority__c, 'Expected each enqueued work item to inherit the configured priority for its job type.');
        }
    }

    @istest static void testCreate_defaultsPriorityToLowestWhenConfigMissingOrBlank() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Async.setMock(new AsyncMock().config(MyBlankPriorityAsync.class, new Async_Config__mdt()));

        List<SObject> contacts = new TestData(Contact.sObjectType)
            .mockIds()
            .count(2)
            .build();

        Async.enqueue(MyTestAsync.class, new Set<Id> { contacts[0].Id });
        Async.enqueue(MyBlankPriorityAsync.class, new Set<Id> { contacts[1].Id });

        List<Async__c> inserted = new List<Async__c>();
        for (List<SObject> batch : dmlMock.inserts) {
            inserted.addAll((List<Async__c>) batch);
        }

        Assert.areEqual(2, inserted.size(), 'Expected one work item per enqueue call.');
        for (Async__c workItem : inserted) {
            Assert.areEqual(0, workItem.Priority__c, 'Expected missing config rows and blank priority values to seed the lowest priority.');
        }
    }

    @istest static void testEnqueueNextJob_drainsHigherPriorityJobTypeFirst() {
        List<Contact> contacts = new List<Contact> {
            new Contact(LastName = 'High Priority'),
            new Contact(LastName = 'Low Priority')
        };
        insert contacts;

        AsyncMock mock = new AsyncMock()
            .config(MyPriorityAsync.class, new Async_Config__mdt(Batch_Size__c = 5, Priority__c = 100))
            .config(MyLowPriorityAsync.class, new Async_Config__mdt(Batch_Size__c = 5, Priority__c = 1));
        Async.setMock(mock);

        Async.enqueue(MyLowPriorityAsync.class, new Set<Id> { contacts[1].Id });
        Async.enqueue(MyPriorityAsync.class, new Set<Id> { contacts[0].Id });

        Test.startTest();
            Async.jobs.enqueueNextJob();

            List<Async__c> runningItems = [
                SELECT Apex__c, Priority__c, Status__c
                FROM Async__c
                WHERE Status__c = 'Running'
            ];
            Assert.areEqual(1, runningItems.size(), 'Expected one batch to be marked Running when the next async job is dispatched.');
            Assert.areEqual(String.valueOf(MyPriorityAsync.class), runningItems[0].Apex__c,
                'Expected the higher-priority job type to dispatch before lower-priority work in the same backlog.');
            Assert.areEqual(100, runningItems[0].Priority__c,
                'Expected the running work item to retain its seeded priority.');
        Test.stopTest();
    }

    @istest static void testSettingsService_cachesResolvedSettingsPerTransaction() {
        CountingSettingsService settings = new CountingSettingsService();

        settings.getSettings();
        settings.getSettings();
        settings.getSettings();

        Assert.areEqual(1, settings.loadCount, 'Expected repeated settings reads in one transaction to load once and serve the transaction cache.');
    }

    @istest static void testSetMock_replacesSettingsService() {
        AsyncMock mock = new AsyncMock().seedSettings(new Async_Settings__c(SetupOwnerId = UserInfo.getUserId()));
        Async.setMock(mock);

        Assert.isTrue(Async.settings instanceof AsyncMock.SettingsService, 'Expected Async.setMock to replace the settings singleton with the mock settings service.');
    }

    @istest static void testSettingsService_returnsSeededValuesWithoutLoad() {
        CountingSettingsService settings = new CountingSettingsService();
        settings.setSettings(new Async_Settings__c(SetupOwnerId = UserInfo.getUserId()));

        Async_Settings__c cached = settings.getSettings();

        Assert.areEqual(0, settings.loadCount, 'Expected seeded settings values to be served from memory without loading org state.');
        Assert.areEqual(UserInfo.getUserId(), cached.SetupOwnerId, 'Expected the seeded settings values to be returned unchanged from memory.');
    }

    @istest static void testShouldAutoRetry_respectsConfiguredCap() {
        AsyncMock mock = new AsyncMock()
            .config(MyTestAsync.class, new Async_Config__mdt(Batch_Size__c = 5, Max_Retries__c = 3));
        Async.setMock(mock);

        Async.JobService jobs = new Async.JobService();
        String apex = String.valueOf(MyTestAsync.class);

        Assert.isTrue(jobs.shouldAutoRetry(new Async__c(Apex__c = apex, Retry_Count__c = 0)),
            'Expected a fresh failure under the cap to auto-retry.');
        Assert.isTrue(jobs.shouldAutoRetry(new Async__c(Apex__c = apex, Retry_Count__c = 2)),
            'Expected a work item one retry below the cap to auto-retry.');
        Assert.isFalse(jobs.shouldAutoRetry(new Async__c(Apex__c = apex, Retry_Count__c = 3)),
            'Expected a work item at the cap to stay terminal Error.');
        Assert.isFalse(jobs.shouldAutoRetry(new Async__c(Apex__c = apex, Retry_Count__c = 5)),
            'Expected a work item over the cap to stay terminal Error.');
    }

    @istest static void testShouldAutoRetry_offWhenMaxAbsentOrZero() {
        AsyncMock mock = new AsyncMock()
            .config(MyTestAsync.class, new Async_Config__mdt(Batch_Size__c = 5, Max_Retries__c = 0));
        Async.setMock(mock);

        Async.JobService jobs = new Async.JobService();

        Assert.isFalse(jobs.shouldAutoRetry(new Async__c(Apex__c = String.valueOf(MyTestAsync.class), Retry_Count__c = 0)),
            'Expected auto-retry off when Max_Retries__c is zero.');
        Assert.isFalse(jobs.shouldAutoRetry(new Async__c(Apex__c = 'Unconfigured_Async_Class', Retry_Count__c = 0)),
            'Expected auto-retry off when no Async_Config__mdt row supplies Max_Retries__c.');
    }

    @istest static void testAutoRetry_incrementsRetryCountAndRepends() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        List<Async__c> workItems = (List<Async__c>) new TestData(Async__c.sObjectType)
            .mockIds()
            .count(2)
            .build();
        workItems[0].Retry_Count__c = 0;
        workItems[1].Retry_Count__c = 4;

        new Async.WorkService().autoRetry(workItems);

        Assert.areEqual(1, dmlMock.updates.size(), 'Expected a single update batch for the auto-retried work items.');

        Map<Id, Async__c> updatedById = new Map<Id, Async__c>();
        for (Async__c updated : (List<Async__c>) dmlMock.updates[0]) {
            updatedById.put(updated.Id, updated);
        }

        Assert.areEqual('Pending', updatedById.get(workItems[0].Id).Status__c, 'Expected the auto-retried work item to be re-pended.');
        Assert.areEqual(1, updatedById.get(workItems[0].Id).Retry_Count__c, 'Expected Retry_Count__c to increment from 0 to 1.');
        Assert.areEqual(5, updatedById.get(workItems[1].Id).Retry_Count__c, 'Expected Retry_Count__c to increment from 4 to 5.');
    }

    @istest static void testHandleFailure_rependsUnderCapAndFailsAtCap() {
        Contact contact = new Contact(LastName = 'Failure');
        insert contact;

        AsyncMock mock = new AsyncMock()
            .config(MyTestAsync.class, new Async_Config__mdt(Batch_Size__c = 5, Max_Retries__c = 2));
        Async.setMock(mock);

        String apex = String.valueOf(MyTestAsync.class);
        String threadId = Request.getCurrent().getRequestId();
        Async__c underCap = new Async__c(Apex__c = apex, Record_Id__c = contact.Id, Status__c = 'Running', Retry_Count__c = 0, Thread__c = threadId);
        Async__c atCap = new Async__c(Apex__c = apex, Record_Id__c = contact.Id, Status__c = 'Running', Retry_Count__c = 2, Thread__c = threadId);
        insert new List<Async__c> { underCap, atCap };

        Async.jobs.handleFailure(new Set<Id> { underCap.Id, atCap.Id }, 'boom', 'stack-trace');

        Async__c retried = [SELECT Status__c, Retry_Count__c FROM Async__c WHERE Id = :underCap.Id];
        Assert.areEqual('Pending', retried.Status__c, 'Expected the under-cap work item to be re-pended for auto-retry.');
        Assert.areEqual(1, retried.Retry_Count__c, 'Expected the under-cap work item Retry_Count__c to increment from 0 to 1.');

        Async__c terminal = [SELECT Status__c, Retry_Count__c, Error_Message__c FROM Async__c WHERE Id = :atCap.Id];
        Assert.areEqual('Error', terminal.Status__c, 'Expected the at-cap work item to rest in terminal Error.');
        Assert.areEqual(2, terminal.Retry_Count__c, 'Expected the at-cap work item Retry_Count__c to stay at the cap.');
        Assert.areEqual('boom', terminal.Error_Message__c, 'Expected the terminal failure to record the error message.');
    }

    @istest static void testHandleFailure_noAutoRetryWhenDisabled() {
        Contact contact = new Contact(LastName = 'Disabled');
        insert contact;

        AsyncMock mock = new AsyncMock()
            .config(MyTestAsync.class, new Async_Config__mdt(Batch_Size__c = 5, Max_Retries__c = 0));
        Async.setMock(mock);

        Async__c item = new Async__c(
            Apex__c = String.valueOf(MyTestAsync.class),
            Record_Id__c = contact.Id,
            Status__c = 'Running',
            Retry_Count__c = 0,
            Thread__c = Request.getCurrent().getRequestId()
        );
        insert item;

        Async.jobs.handleFailure(new Set<Id> { item.Id }, 'boom', 'stack-trace');

        Async__c result = [SELECT Status__c, Retry_Count__c FROM Async__c WHERE Id = :item.Id];
        Assert.areEqual('Error', result.Status__c, 'Expected a terminal Error when auto-retry is disabled.');
        Assert.areEqual(0, result.Retry_Count__c, 'Expected Retry_Count__c to stay 0 when auto-retry is disabled.');
    }

    @istest static void testJobWatcher_continueAfterSuccess_resetsFailureCount() {
        SpyJobService jobs = new SpyJobService();
        Async.jobs = jobs;

        new Async.JobWatcher(Request.getCurrent().getRequestId(), new Set<Id>(), 3).continueAfterSuccess();

        Assert.areEqual(1, jobs.enqueueNextJobCalls, 'Expected success-path dispatch to keep chaining directly to the next worker batch.');
        Assert.areEqual(0, jobs.lastEnqueueNextJobFailureCount, 'Expected success-path dispatch to reset the failure streak before the next worker batch.');
        Assert.areEqual(0, jobs.startThreadCalls, 'Expected success-path dispatch not to restart the thread through AsyncThread.');
    }

    @istest static void testJobWatcher_continueAfterFailure_underThreshold_keepsDirectChain() {
        SpyJobService jobs = new SpyJobService();
        Async.jobs = jobs;

        new Async.JobWatcher(Request.getCurrent().getRequestId(), new Set<Id>(), 2).continueAfterFailure();

        Assert.areEqual(1, jobs.enqueueNextJobCalls, 'Expected failure-path dispatch below the threshold to continue the current worker chain.');
        Assert.areEqual(3, jobs.lastEnqueueNextJobFailureCount, 'Expected failure-path dispatch below the threshold to increment the failure streak for the next worker batch.');
        Assert.areEqual(0, jobs.startThreadCalls, 'Expected failure-path dispatch below the threshold not to restart through AsyncThread yet.');
    }

    @istest static void testJobWatcher_continueAfterFailure_atThreshold_restartsThroughAsyncThread() {
        SpyJobService jobs = new SpyJobService();
        Async.jobs = jobs;

        new Async.JobWatcher(Request.getCurrent().getRequestId(), new Set<Id>(), 3).continueAfterFailure();

        Assert.areEqual(0, jobs.enqueueNextJobCalls, 'Expected failure-path dispatch at the threshold not to chain another worker directly from the finalizer.');
        Assert.areEqual(1, jobs.startThreadCalls, 'Expected failure-path dispatch to restart the backlog through AsyncThread.');
        Assert.areEqual(0, jobs.lastStartThreadFailureCount, 'Expected failure-path dispatch at the threshold to reset the failure streak on the restarted thread.');
    }

    @istest static void testAsyncThread_execute_passesFailureCountToNextWorkerDispatch() {
        SpyJobService jobs = new SpyJobService();
        Async.jobs = jobs;

        new AsyncThread('thread-123', 2).execute(null);

        Assert.areEqual('thread-123', Async.jobs.threadId, 'Expected AsyncThread to adopt the provided thread id before dispatching the next worker batch.');
        Assert.areEqual(1, jobs.enqueueNextJobCalls, 'Expected AsyncThread to dispatch the next worker batch once.');
        Assert.areEqual(2, jobs.lastEnqueueNextJobFailureCount, 'Expected AsyncThread to forward the carried failure streak into the next worker dispatch.');
    }

    @istest static void testManualRetry_pastCapDoesNotBumpRetryCount() {
        Contact contact = new Contact(LastName = 'Manual');
        insert contact;

        AsyncMock mock = new AsyncMock()
            .canEnqueue()
            .config(MyTestAsync.class, new Async_Config__mdt(Batch_Size__c = 5, Max_Retries__c = 2));
        Async.setMock(mock);

        Async__c workItem = new Async__c(
            Apex__c = String.valueOf(MyTestAsync.class),
            Record_Id__c = contact.Id,
            Status__c = 'Error',
            Retry_Count__c = 5,
            Thread__c = Request.getCurrent().getRequestId()
        );
        insert workItem;

        Test.startTest();
            update new Async__c(Id = workItem.Id, Status__c = 'Pending');
        Test.stopTest();

        Async__c result = [SELECT Status__c, Retry_Count__c FROM Async__c WHERE Id = :workItem.Id];
        Assert.areEqual('Done', result.Status__c, 'Expected a manual re-queue past the cap to be honored and run to completion.');
        Assert.areEqual(5, result.Retry_Count__c, 'Expected a manual re-queue not to increment Retry_Count__c.');
    }

    public with sharing class CountingMetadataService extends Async.MetadataService {
        public Integer loadCount = 0;

        protected override Async_Config__mdt loadConfig(String apexClass) {
            this.loadCount++;
            return new Async_Config__mdt(Batch_Size__c = 5);
        }
    }

    public with sharing class CountingSettingsService extends Async.SettingsService {
        public Integer loadCount = 0;

        protected override Async_Settings__c loadSettings() {
            this.loadCount++;
            return new Async_Settings__c();
        }
    }

    public with sharing class SpyJobService extends Async.JobService {
        public Integer enqueueNextJobCalls = 0;
        public Integer startThreadCalls = 0;
        public Integer lastEnqueueNextJobFailureCount = -1;
        public Integer lastStartThreadFailureCount = -1;

        public override void enqueueNextJob(Integer failureCount) {
            this.enqueueNextJobCalls++;
            this.lastEnqueueNextJobFailureCount = failureCount;
        }

        public override void startThread(Integer failureCount) {
            this.startThreadCalls++;
            this.lastStartThreadFailureCount = failureCount;
        }
    }

    public with sharing class MyTestAsync extends Async {
        public override void execute(Set<Id> ids) {
            List<Contact> contacts = [SELECT Id, FirstName, LastName FROM Contact WHERE Id IN :ids];
            for(Contact contact : contacts) {
                contact.FirstName = 'Hello';
            }
            update contacts;
        }
    }

    public with sharing class SetupSafeParentAsync extends Async {
        public override void execute(Set<Id> ids) {
            String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '0');
            DML.insertRecords(new List<SObject> {
                new Group(
                    Name = 'Async Setup Safe ' + suffix,
                    DeveloperName = 'Async_Setup_Safe_' + suffix,
                    Type = 'Regular'
                )
            });

            Async.enqueue(SetupSafeChildAsync.class, ids);
            Async.enqueue(SetupSafeChildAsync.class, ids);
        }
    }

    public with sharing class SetupSafeStagedParentAsync extends Async {
        public override void execute(Set<Id> ids) {
            String suffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '0');
            DML.insertRecords(new List<SObject> {
                new Group(
                    Name = 'Async Staged Setup Safe ' + suffix,
                    DeveloperName = 'Async_Staged_Setup_Safe_' + suffix,
                    Type = 'Regular'
                )
            });

            Async.stage(SetupSafeChildAsync.class, ids);
            Async.stage(SetupSafeChildAsync.class, ids);
            Async.flush();
        }
    }

    public with sharing class SetupSafeChildAsync extends Async {
        public override void execute(Set<Id> ids) {
            List<Contact> contacts = [SELECT Id, FirstName FROM Contact WHERE Id IN :ids];
            for(Contact contact : contacts) {
                contact.FirstName = 'Child';
            }
            update contacts;
        }
    }

    public with sharing class MyPriorityAsync extends Async {
        public override void execute(Set<Id> ids) {
        }
    }

    public with sharing class MyBlankPriorityAsync extends Async {
        public override void execute(Set<Id> ids) {
        }
    }

    public with sharing class MyLowPriorityAsync extends Async {
        public override void execute(Set<Id> ids) {
        }
    }
}
