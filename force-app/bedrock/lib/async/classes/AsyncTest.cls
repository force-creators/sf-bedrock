/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:Async')
public with sharing class AsyncTest {
    @istest
    static void testMock() {
        List<Contact> contacts = new List<Contact>{
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

        for (Async__c workItem : [SELECT Id, Status__c FROM Async__c]) {
            Assert.areEqual(
                'Done',
                workItem.Status__c,
                'Expected all async work items to be marked done after the queueable chain finishes.'
            );
        }

        for (Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual(
                'Hello',
                contact.FirstName,
                'Expected the async job to update each staged contact.'
            );
        }
    }

    @istest
    static void testEnqueueFromAsync_defersChildWorkUntilFinalizer() {
        List<Contact> contacts = new List<Contact>{
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
            Assert.areEqual(
                'Done',
                workItem.Status__c,
                'Expected parent and child work items to finish successfully.'
            );
            if (!workItemsByApex.containsKey(workItem.Apex__c)) {
                workItemsByApex.put(workItem.Apex__c, 0);
            }
            workItemsByApex.put(
                workItem.Apex__c,
                workItemsByApex.get(workItem.Apex__c) + 1
            );
        }

        Assert.areEqual(
            2,
            workItemsByApex.get(String.valueOf(SetupSafeParentAsync.class)),
            'Expected one parent work item for each contact.'
        );
        Assert.areEqual(
            2,
            workItemsByApex.get(String.valueOf(SetupSafeChildAsync.class)),
            'Expected child work to be created from the finalizer after setup DML.'
        );

        for (Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual(
                'Child',
                contact.FirstName,
                'Expected child async work to run after parent setup-object DML succeeds.'
            );
        }
    }

    @istest
    static void testStageAndFlush_createsWorkInSingleDmlTransaction() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Async.setMock(new AsyncMock().mockThreadIds());

        List<SObject> contacts = new TestData(Contact.sObjectType)
            .mockIds()
            .count(2)
            .build();
        Set<Id> contactIds = Pluck.ids(contacts);

        Async.stage(MyTestAsync.class, new Set<Id>{ contacts[0].Id });
        Async.stage(MyTestAsync.class, contactIds);
        Async.stage(SetupSafeChildAsync.class, contactIds);
        Async.flush();

        List<List<SObject>> asyncInsertBatches = insertBatchesFor(
            dmlMock,
            Async__c.sObjectType
        );
        Assert.areEqual(
            1,
            asyncInsertBatches.size(),
            'Expected flush() to create all staged async work in one DML insert call.'
        );
        Assert.areEqual(
            4,
            asyncInsertBatches[0].size(),
            'Expected flush() to merge duplicate staged ids by Apex class before creating work items.'
        );
    }

    @istest
    static void testStageAndFlushFromAsync_defersChildWorkUntilFinalizer() {
        List<Contact> contacts = new List<Contact>{
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
            Assert.areEqual(
                'Done',
                workItem.Status__c,
                'Expected staged parent and child work items to finish successfully.'
            );
            if (!workItemsByApex.containsKey(workItem.Apex__c)) {
                workItemsByApex.put(workItem.Apex__c, 0);
            }
            workItemsByApex.put(
                workItem.Apex__c,
                workItemsByApex.get(workItem.Apex__c) + 1
            );
        }

        Assert.areEqual(
            2,
            workItemsByApex.get(
                String.valueOf(SetupSafeStagedParentAsync.class)
            ),
            'Expected one staged parent work item for each contact.'
        );
        Assert.areEqual(
            2,
            workItemsByApex.get(String.valueOf(SetupSafeChildAsync.class)),
            'Expected staged child work to be created from the finalizer after setup DML.'
        );

        for (Contact contact : [SELECT Id, FirstName FROM Contact]) {
            Assert.areEqual(
                'Child',
                contact.FirstName,
                'Expected staged child async work to run after parent setup-object DML succeeds.'
            );
        }
    }

    @istest
    static void testMetadataService_cachesConfigReadsForSameJobType() {
        CountingMetadataService metadata = new CountingMetadataService();

        metadata.getConfig('Some_Async_Class');
        metadata.getConfig('Some_Async_Class');
        metadata.getConfig('Some_Async_Class');

        Assert.areEqual(
            1,
            metadata.loadCount,
            'Expected repeated config reads for the same job type to load once and serve the transaction cache.'
        );

        metadata.getConfig('Another_Async_Class');

        Assert.areEqual(
            2,
            metadata.loadCount,
            'Expected a distinct job type to trigger one additional load.'
        );
    }

    @istest
    static void testMetadataService_fallsBackToDefaultWhenNoConfigRow() {
        Async_Job__mdt config = new Async.MetadataService()
            .getConfig('No_Such_Async_Job_Row');

        Assert.areEqual(
            5,
            config.Batch_Size__c,
            'Expected the default batch size when no Async_Job__mdt row exists for the job type.'
        );
        Assert.areEqual(
            null,
            config.Max_Retries__c,
            'Expected no Max_Retries__c on the default config so auto-retry stays off.'
        );
        Assert.areEqual(
            null,
            config.Priority__c,
            'Expected no Priority__c on the default config so unconfigured work has no assigned priority.'
        );
    }

    @istest
    static void testCreate_seedsConfiguredPriorityOnWorkItems() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Async.setMock(
            new AsyncMock()
                .mockThreadIds()
                .config(
                    MyPriorityAsync.class,
                    new Async_Job__mdt(Priority__c = 42)
                )
        );

        List<SObject> contacts = new TestData(Contact.sObjectType)
            .mockIds()
            .count(2)
            .build();

        Async.enqueue(MyPriorityAsync.class, Pluck.ids(contacts));

        List<List<SObject>> asyncInsertBatches = insertBatchesFor(
            dmlMock,
            Async__c.sObjectType
        );
        Assert.areEqual(
            1,
            asyncInsertBatches.size(),
            'Expected one async insert batch when enqueuing seeded work items.'
        );
        for (Async__c workItem : (List<Async__c>) asyncInsertBatches[0]) {
            Assert.areEqual(
                42,
                workItem.Priority__c,
                'Expected each enqueued work item to inherit the configured priority for its job type.'
            );
        }
    }

    @istest
    static void testCreate_leavesPriorityUnassignedWhenConfigMissingOrBlank() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        Async.setMock(
            new AsyncMock()
                .mockThreadIds()
                .config(MyBlankPriorityAsync.class, new Async_Job__mdt())
        );

        List<SObject> contacts = new TestData(Contact.sObjectType)
            .mockIds()
            .count(2)
            .build();

        Async.enqueue(MyTestAsync.class, new Set<Id>{ contacts[0].Id });
        Async.enqueue(
            MyBlankPriorityAsync.class,
            new Set<Id>{ contacts[1].Id }
        );

        List<Async__c> inserted = new List<Async__c>();
        for (
            List<SObject> batch : insertBatchesFor(
                dmlMock,
                Async__c.sObjectType
            )
        ) {
            inserted.addAll((List<Async__c>) batch);
        }

        Assert.areEqual(
            2,
            inserted.size(),
            'Expected one work item per enqueue call.'
        );
        for (Async__c workItem : inserted) {
            Assert.areEqual(
                null,
                workItem.Priority__c,
                'Expected missing config rows and blank priority values to leave priority unassigned.'
            );
        }
    }

    @istest
    static void testEnqueueNextJob_drainsLowestAssignedPriorityFirst() {
        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = 'Positive Priority'),
            new Contact(LastName = 'Negative Priority')
        };
        insert contacts;

        AsyncMock mock = new AsyncMock()
            .config(
                MyPriorityAsync.class,
                new Async_Job__mdt(Batch_Size__c = 5, Priority__c = 100)
            )
            .config(
                MyLowPriorityAsync.class,
                new Async_Job__mdt(Batch_Size__c = 5, Priority__c = -10)
            );
        Async.setMock(mock);

        Async.enqueue(MyLowPriorityAsync.class, new Set<Id>{ contacts[1].Id });
        Async.enqueue(MyPriorityAsync.class, new Set<Id>{ contacts[0].Id });

        Test.startTest();
        Async.jobs.enqueueNextJob();

        List<Async__c> runningItems = [
            SELECT Apex__c, Priority__c, Status__c
            FROM Async__c
            WHERE Status__c = 'Running'
        ];
        Assert.areEqual(
            1,
            runningItems.size(),
            'Expected one batch to be marked Running when the next async job is dispatched.'
        );
        Assert.areEqual(
            String.valueOf(MyLowPriorityAsync.class),
            runningItems[0].Apex__c,
            'Expected the lowest assigned priority job type to dispatch before higher-priority work in the same backlog.'
        );
        Assert.areEqual(
            -10,
            runningItems[0].Priority__c,
            'Expected the running work item to retain its seeded priority.'
        );
        Test.stopTest();
    }

    @istest
    static void testQueryService_sortsPriorityAscendingAndNullsLast() {
        Async.setMock(new AsyncMock());
        Id threadId = Thread.currentOrCreate();
        Id recordId = UserInfo.getUserId();
        String apexClass = String.valueOf(MyPriorityAsync.class);
        Async__c unassignedPriority = workItem(
            apexClass,
            recordId,
            'Pending',
            threadId
        );
        Async__c positivePriority = workItem(
            apexClass,
            recordId,
            'Pending',
            threadId
        );
        positivePriority.Priority__c = 10;
        Async__c negativePriority = workItem(
            apexClass,
            recordId,
            'Pending',
            threadId
        );
        negativePriority.Priority__c = -10;
        insert new List<Async__c>{
            unassignedPriority,
            positivePriority,
            negativePriority
        };

        Async.QueryService queries = new Async.QueryService();
        Async__c nextWorkItem = queries.getNextWorkItem(threadId);
        List<Async__c> matchingWorkItems = queries.getMatchingWorkItems(
            threadId,
            apexClass,
            3
        );

        Assert.areEqual(
            -10,
            nextWorkItem.Priority__c,
            'Expected the next work item query to sort assigned priorities from lowest to highest.'
        );
        Assert.areEqual(
            -10,
            matchingWorkItems[0].Priority__c,
            'Expected matching work items to start with the lowest assigned priority.'
        );
        Assert.areEqual(
            10,
            matchingWorkItems[1].Priority__c,
            'Expected positive assigned priorities to run after lower assigned priorities.'
        );
        Assert.areEqual(
            null,
            matchingWorkItems[2].Priority__c,
            'Expected unassigned priority work items to sort after assigned priorities.'
        );
    }

    @istest
    static void testSettingsService_cachesResolvedSettingsPerTransaction() {
        CountingSettingsService settings = new CountingSettingsService();

        settings.getSettings();
        settings.getSettings();
        settings.getSettings();

        Assert.areEqual(
            1,
            settings.loadCount,
            'Expected repeated settings reads in one transaction to load once and serve the transaction cache.'
        );
    }

    @istest
    static void testSetMock_replacesSettingsService() {
        AsyncMock mock = new AsyncMock()
            .seedSettings(
                new Async_Settings__c(SetupOwnerId = UserInfo.getUserId())
            );
        Async.setMock(mock);

        Assert.isTrue(
            Async.settings instanceof AsyncMock.SettingsService,
            'Expected Async.setMock to replace the settings singleton with the mock settings service.'
        );
    }

    @istest
    static void testSettingsService_returnsSeededValuesWithoutLoad() {
        CountingSettingsService settings = new CountingSettingsService();
        settings.setSettings(
            new Async_Settings__c(SetupOwnerId = UserInfo.getUserId())
        );

        Async_Settings__c cached = settings.getSettings();

        Assert.areEqual(
            0,
            settings.loadCount,
            'Expected seeded settings values to be served from memory without loading org state.'
        );
        Assert.areEqual(
            UserInfo.getUserId(),
            cached.SetupOwnerId,
            'Expected the seeded settings values to be returned unchanged from memory.'
        );
    }

    @istest
    static void testSettingsService_maxThreadsDefaultsToOne() {
        Async.SettingsService settings = new Async.SettingsService();

        settings.setSettings(new Async_Settings__c());
        Assert.areEqual(
            1,
            settings.maxThreads(),
            'Expected blank Max Threads to default to one active thread.'
        );

        settings.setSettings(new Async_Settings__c(Max_Threads__c = 0));
        Assert.areEqual(
            1,
            settings.maxThreads(),
            'Expected non-positive Max Threads to default to one active thread.'
        );
    }

    @istest
    static void testSettingsService_archiveThresholdHoursDefaultsToOneDay() {
        Async.SettingsService settings = new Async.SettingsService();

        settings.setSettings(new Async_Settings__c());
        Assert.areEqual(
            24,
            settings.archiveThresholdHours(),
            'Expected blank Archive Threshold Hours to default to one day.'
        );

        settings.setSettings(
            new Async_Settings__c(Archive_Threshold_Hours__c = 0)
        );
        Assert.areEqual(
            0,
            settings.archiveThresholdHours(),
            'Expected zero Archive Threshold Hours to archive completed work immediately.'
        );

        settings.setSettings(
            new Async_Settings__c(Archive_Threshold_Hours__c = 6)
        );
        Assert.areEqual(
            6,
            settings.archiveThresholdHours(),
            'Expected configured Archive Threshold Hours to be returned as whole hours.'
        );
    }

    @istest
    static void testSettingsService_archiveCleanupDefaultsToDisabled() {
        Async.SettingsService settings = new Async.SettingsService();

        settings.setSettings(new Async_Settings__c());
        Assert.isFalse(
            settings.archiveCleanupEnabled(),
            'Expected archive cleanup to default off.'
        );
        Assert.areEqual(
            30,
            settings.maxArchiveAgeDays(),
            'Expected blank Max Archive Age to default to 30 days.'
        );

        settings.setSettings(
            new Async_Settings__c(
                Enable_Archive_Cleanup__c = true,
                Max_Archive_Age__c = 0
            )
        );
        Assert.isTrue(
            settings.archiveCleanupEnabled(),
            'Expected enabled archive cleanup setting to be honored.'
        );
        Assert.areEqual(
            0,
            settings.maxArchiveAgeDays(),
            'Expected zero Max Archive Age to clean archived rows immediately.'
        );
    }

    @istest
    static void testShouldAutoRetry_respectsConfiguredCap() {
        AsyncMock mock = new AsyncMock()
            .config(
                MyTestAsync.class,
                new Async_Job__mdt(Batch_Size__c = 5, Max_Retries__c = 3)
            );
        Async.setMock(mock);

        Async.JobService jobs = new Async.JobService();
        String apex = String.valueOf(MyTestAsync.class);

        Assert.isTrue(
            jobs.shouldAutoRetry(
                new Async__c(Apex__c = apex, Retry_Count__c = 0)
            ),
            'Expected a fresh failure under the cap to auto-retry.'
        );
        Assert.isTrue(
            jobs.shouldAutoRetry(
                new Async__c(Apex__c = apex, Retry_Count__c = 2)
            ),
            'Expected a work item one retry below the cap to auto-retry.'
        );
        Assert.isFalse(
            jobs.shouldAutoRetry(
                new Async__c(Apex__c = apex, Retry_Count__c = 3)
            ),
            'Expected a work item at the cap to stay terminal Error.'
        );
        Assert.isFalse(
            jobs.shouldAutoRetry(
                new Async__c(Apex__c = apex, Retry_Count__c = 5)
            ),
            'Expected a work item over the cap to stay terminal Error.'
        );
    }

    @istest
    static void testShouldAutoRetry_offWhenMaxAbsentOrZero() {
        AsyncMock mock = new AsyncMock()
            .config(
                MyTestAsync.class,
                new Async_Job__mdt(Batch_Size__c = 5, Max_Retries__c = 0)
            );
        Async.setMock(mock);

        Async.JobService jobs = new Async.JobService();

        Assert.isFalse(
            jobs.shouldAutoRetry(
                new Async__c(
                    Apex__c = String.valueOf(MyTestAsync.class),
                    Retry_Count__c = 0
                )
            ),
            'Expected auto-retry off when Max_Retries__c is zero.'
        );
        Assert.isFalse(
            jobs.shouldAutoRetry(
                new Async__c(
                    Apex__c = 'Unconfigured_Async_Class',
                    Retry_Count__c = 0
                )
            ),
            'Expected auto-retry off when no Async_Job__mdt row supplies Max_Retries__c.'
        );
    }

    @istest
    static void testAutoRetry_incrementsRetryCountAndRepends() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        List<Async__c> workItems = (List<Async__c>) new TestData(
                Async__c.sObjectType
            )
            .mockIds()
            .count(2)
            .build();
        workItems[0].Retry_Count__c = 0;
        workItems[1].Retry_Count__c = 4;

        new Async.WorkService().autoRetry(workItems);

        Assert.areEqual(
            1,
            dmlMock.updates.size(),
            'Expected a single update batch for the auto-retried work items.'
        );

        Map<Id, Async__c> updatedById = new Map<Id, Async__c>();
        for (Async__c updated : (List<Async__c>) dmlMock.updates[0]) {
            updatedById.put(updated.Id, updated);
        }

        Assert.areEqual(
            'Pending',
            updatedById.get(workItems[0].Id).Status__c,
            'Expected the auto-retried work item to be re-pended.'
        );
        Assert.areEqual(
            1,
            updatedById.get(workItems[0].Id).Retry_Count__c,
            'Expected Retry_Count__c to increment from 0 to 1.'
        );
        Assert.areEqual(
            5,
            updatedById.get(workItems[1].Id).Retry_Count__c,
            'Expected Retry_Count__c to increment from 4 to 5.'
        );
    }

    @istest
    static void testHandleFailure_rependsUnderCapAndFailsAtCap() {
        Contact contact = new Contact(LastName = 'Failure');
        insert contact;

        AsyncMock mock = new AsyncMock()
            .config(
                MyTestAsync.class,
                new Async_Job__mdt(Batch_Size__c = 5, Max_Retries__c = 2)
            );
        Async.setMock(mock);

        String apex = String.valueOf(MyTestAsync.class);
        Id threadId = Thread.currentOrCreate();
        Async__c underCap = workItem(apex, contact.Id, 'Running', threadId);
        underCap.Retry_Count__c = 0;
        Async__c atCap = workItem(apex, contact.Id, 'Running', threadId);
        atCap.Retry_Count__c = 2;
        insert new List<Async__c>{ underCap, atCap };

        Async.jobs.handleFailure(
            new Set<Id>{ underCap.Id, atCap.Id },
            'boom',
            'stack-trace'
        );

        Async__c retried = [
            SELECT Status__c, Retry_Count__c
            FROM Async__c
            WHERE Id = :underCap.Id
        ];
        Assert.areEqual(
            'Pending',
            retried.Status__c,
            'Expected the under-cap work item to be re-pended for auto-retry.'
        );
        Assert.areEqual(
            1,
            retried.Retry_Count__c,
            'Expected the under-cap work item Retry_Count__c to increment from 0 to 1.'
        );

        Async__c terminal = [
            SELECT Status__c, Retry_Count__c, Error_Message__c
            FROM Async__c
            WHERE Id = :atCap.Id
        ];
        Assert.areEqual(
            'Error',
            terminal.Status__c,
            'Expected the at-cap work item to rest in terminal Error.'
        );
        Assert.areEqual(
            2,
            terminal.Retry_Count__c,
            'Expected the at-cap work item Retry_Count__c to stay at the cap.'
        );
        Assert.areEqual(
            'boom',
            terminal.Error_Message__c,
            'Expected the terminal failure to record the error message.'
        );
    }

    @istest
    static void testHandleFailure_noAutoRetryWhenDisabled() {
        Contact contact = new Contact(LastName = 'Disabled');
        insert contact;

        AsyncMock mock = new AsyncMock()
            .config(
                MyTestAsync.class,
                new Async_Job__mdt(Batch_Size__c = 5, Max_Retries__c = 0)
            );
        Async.setMock(mock);

        Async__c item = workItem(
            String.valueOf(MyTestAsync.class),
            contact.Id,
            'Running',
            Thread.currentOrCreate()
        );
        item.Retry_Count__c = 0;
        insert item;

        Async.jobs.handleFailure(new Set<Id>{ item.Id }, 'boom', 'stack-trace');

        Async__c result = [
            SELECT Status__c, Retry_Count__c
            FROM Async__c
            WHERE Id = :item.Id
        ];
        Assert.areEqual(
            'Error',
            result.Status__c,
            'Expected a terminal Error when auto-retry is disabled.'
        );
        Assert.areEqual(
            0,
            result.Retry_Count__c,
            'Expected Retry_Count__c to stay 0 when auto-retry is disabled.'
        );
    }

    @istest
    static void testAsyncJob_canExplicitlyFailOneRecordAndCompleteTheRest() {
        List<Contact> contacts = new List<Contact>{
            new Contact(LastName = 'A Explicit Complete'),
            new Contact(LastName = 'B Explicit Fail'),
            new Contact(LastName = 'C Default Complete')
        };
        insert contacts;

        AsyncMock mock = new AsyncMock()
            .canEnqueue()
            .config(
                PartialResultAsync.class,
                new Async_Job__mdt(Batch_Size__c = 3, Max_Retries__c = 0)
            );
        Async.setMock(mock);

        Test.startTest();
        Async.enqueue(PartialResultAsync.class, contacts);
        Test.stopTest();

        Set<String> recordIdValues = new Set<String>();
        for (Id contactId : Pluck.ids(contacts)) {
            recordIdValues.add(String.valueOf(contactId));
        }
        Map<Id, Async__c> workByRecordId = new Map<Id, Async__c>();
        for (Async__c workItem : [
            SELECT Record_Id__c, Status__c, Error_Message__c
            FROM Async__c
            WHERE Record_Id__c IN :recordIdValues
        ]) {
            workByRecordId.put((Id) workItem.Record_Id__c, workItem);
        }

        Assert.areEqual(
            'Done',
            workByRecordId.get(contacts[0].Id).Status__c,
            'Expected explicitly completed async work to be marked done.'
        );
        Assert.areEqual(
            'Error',
            workByRecordId.get(contacts[1].Id).Status__c,
            'Expected explicitly failed async work to be marked error without failing the whole batch.'
        );
        Assert.areEqual(
            'partial failure',
            workByRecordId.get(contacts[1].Id).Error_Message__c,
            'Expected explicitly failed async work to preserve the failure message.'
        );
        Assert.areEqual(
            'Done',
            workByRecordId.get(contacts[2].Id).Status__c,
            'Expected async work with no explicit result to be marked done.'
        );

        Map<Id, Contact> contactsById = new Map<Id, Contact>(
            [
                SELECT Id, FirstName
                FROM Contact
                WHERE Id IN :Pluck.ids(contacts)
            ]
        );
        Assert.areEqual(
            'Explicit',
            contactsById.get(contacts[0].Id).FirstName,
            'Expected the explicitly completed record to keep the job mutation.'
        );
        Assert.areEqual(
            null,
            contactsById.get(contacts[1].Id).FirstName,
            'Expected the explicitly failed record not to receive the success mutation.'
        );
        Assert.areEqual(
            'Default',
            contactsById.get(contacts[2].Id).FirstName,
            'Expected the default-completed record to keep the job mutation.'
        );
    }

    @istest
    static void testJobWatcher_continueAfterFailure_underThreshold_keepsDirectChain() {
        SpyJobService jobs = new SpyJobService();
        Async.jobs = jobs;
        ThreadMock threads = new ThreadMock().mockIds();
        Thread.setMock(threads);
        Thread.currentOrCreate();
        Async.queries = new PendingWorkQueryService();

        new Async.JobWatcher(Thread.currentId(), new Set<Id>(), 2)
            .continueAfterFailure();

        Assert.areEqual(
            1,
            jobs.enqueueNextJobCalls,
            'Expected failure-path dispatch below the threshold to continue the current worker chain.'
        );
        Assert.areEqual(
            3,
            jobs.lastEnqueueFailures,
            'Expected failure-path dispatch below the threshold to increment the failure streak for the next worker batch.'
        );
        Assert.areEqual(
            0,
            threads.service.startCalls,
            'Expected failure-path dispatch below the threshold not to restart through ThreadRunner yet.'
        );
    }

    @istest
    static void testJobWatcher_continueAfterFailure_atThreshold_restartsThroughAsyncThread() {
        SpyJobService jobs = new SpyJobService();
        Async.jobs = jobs;
        ThreadMock threads = new ThreadMock().mockIds();
        Thread.setMock(threads);
        Id threadId = Thread.currentOrCreate();
        Async.queries = new PendingWorkQueryService();

        new Async.JobWatcher(threadId, new Set<Id>(), 3).continueAfterFailure();

        Assert.areEqual(
            0,
            jobs.enqueueNextJobCalls,
            'Expected failure-path dispatch at the threshold not to chain another worker directly from the finalizer.'
        );
        Assert.areEqual(
            1,
            threads.service.startCalls,
            'Expected failure-path dispatch to restart the backlog through ThreadRunner.'
        );
        Assert.areEqual(
            0,
            threads.service.lastFailures,
            'Expected failure-path dispatch at the threshold to reset the failure streak on the restarted thread.'
        );
    }

    @istest
    static void testAsyncThread_execute_passesFailureCountToNextWorkerDispatch() {
        SpyJobService jobs = new SpyJobService();
        Async.jobs = jobs;
        Thread__c threadRecord = new Thread__c(
            Status__c = Thread.consts.RUNNING,
            Run_Key__c = 'active-run-key'
        );
        insert threadRecord;

        new AsyncThread(threadRecord.Id, 2, 'active-run-key').execute(null);

        Assert.areEqual(
            threadRecord.Id,
            Thread.currentId(),
            'Expected AsyncThread to adopt the provided thread id before dispatching the next worker batch.'
        );
        Assert.areEqual(
            1,
            jobs.enqueueNextJobCalls,
            'Expected AsyncThread to dispatch the next worker batch once.'
        );
        Assert.areEqual(
            2,
            jobs.lastEnqueueFailures,
            'Expected AsyncThread to forward the carried failure streak into the next worker dispatch.'
        );
    }

    @istest
    static void testManualRetry_pastCapDoesNotBumpRetryCount() {
        Contact contact = new Contact(LastName = 'Manual');
        insert contact;

        AsyncMock mock = new AsyncMock()
            .canEnqueue()
            .config(
                MyTestAsync.class,
                new Async_Job__mdt(Batch_Size__c = 5, Max_Retries__c = 2)
            );
        Async.setMock(mock);

        Async__c workItem = workItem(
            String.valueOf(MyTestAsync.class),
            contact.Id,
            'Error',
            Thread.currentOrCreate()
        );
        workItem.Retry_Count__c = 5;
        insert workItem;

        Test.startTest();
        update new Async__c(Id = workItem.Id, Status__c = 'Pending');
        Test.stopTest();

        Async__c result = [
            SELECT Status__c, Retry_Count__c
            FROM Async__c
            WHERE Id = :workItem.Id
        ];
        Assert.areEqual(
            'Done',
            result.Status__c,
            'Expected a manual re-queue past the cap to be honored and run to completion.'
        );
        Assert.areEqual(
            5,
            result.Retry_Count__c,
            'Expected a manual re-queue not to increment Retry_Count__c.'
        );
    }

    @istest
    static void testThreadDispatcher_treatsRunningWorkAsRecoverable() {
        Contact contact = new Contact(LastName = 'Recoverable');
        insert contact;
        Id threadId = Thread.currentOrCreate();
        insert workItem(
            String.valueOf(MyTestAsync.class),
            contact.Id,
            'Running',
            threadId
        );

        Boolean hasRecoverableWork = new Async.ThreadDispatcher()
            .hasRecoverableWork(threadId);

        Assert.isTrue(
            hasRecoverableWork,
            'Expected stranded Running async work to be recoverable by Thread recovery.'
        );
    }

    @istest
    static void testThreadDispatcher_prepareRecoveryRependsRunningWork() {
        Contact contact = new Contact(LastName = 'Reset');
        insert contact;
        Id threadId = Thread.currentOrCreate();
        Async__c runningWork = workItem(
            String.valueOf(MyTestAsync.class),
            contact.Id,
            'Running',
            threadId
        );
        insert runningWork;

        new Async.ThreadDispatcher().prepareRecovery(threadId);

        Async__c recoveredWork = [
            SELECT Status__c
            FROM Async__c
            WHERE Id = :runningWork.Id
        ];
        Assert.areEqual(
            'Pending',
            recoveredWork.Status__c,
            'Expected Async recovery preparation to make stranded Running work runnable again.'
        );
    }

    @istest
    static void testJobService_pausesThreadWhenAsyncLimitIsUnsafe() {
        Limiter.setMock(
            new LimiterMock()
                .setLimit(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS, 90, 100)
        );
        Contact contact = new Contact(LastName = 'Limit Pause');
        insert contact;
        Thread__c threadRecord = new Thread__c(
            Status__c = Thread.consts.RUNNING,
            Pool__c = Thread.consts.ASYNC_POOL,
            Thread_Key__c = 'request:limit-pause',
            Run_Key__c = 'run-key',
            Heartbeat__c = System.now()
        );
        insert threadRecord;
        Async__c work = workItem(
            String.valueOf(MyTestAsync.class),
            contact.Id,
            'Pending',
            threadRecord.Id
        );
        insert work;

        Async.jobs.enqueueNextJob(threadRecord.Id, 0, 'run-key');

        Async__c storedWork = [
            SELECT Status__c
            FROM Async__c
            WHERE Id = :work.Id
        ];
        Thread__c storedThread = [
            SELECT Status__c, Pause_Reason__c, Run_Key__c
            FROM Thread__c
            WHERE Id = :threadRecord.Id
        ];
        Assert.areEqual(
            'Pending',
            storedWork.Status__c,
            'Unsafe async limits should leave async work pending.'
        );
        Assert.areEqual(
            Thread.consts.PAUSED,
            storedThread.Status__c,
            'Unsafe async limits should pause the owning thread.'
        );
        Assert.areEqual(
            'Daily async Apex execution limit is not safe.',
            storedThread.Pause_Reason__c,
            'Expected the paused thread to explain the limiter pause.'
        );
        Assert.isNull(
            storedThread.Run_Key__c,
            'Pausing a thread should fence the current run key.'
        );
    }

    public with sharing class CountingMetadataService extends Async.MetadataService {
        public Integer loadCount = 0;

        protected override Async_Job__mdt loadConfig(String apexClass) {
            this.loadCount++;
            return new Async_Job__mdt(Batch_Size__c = 5);
        }
    }

    public with sharing class CountingSettingsService extends Async.SettingsService {
        public Integer loadCount = 0;

        protected override Async_Settings__c loadSettings() {
            this.loadCount++;
            return new Async_Settings__c();
        }
    }

    public with sharing class PendingWorkQueryService extends Async.QueryService {
        public override Boolean hasPendingWork(Id threadId) {
            return true;
        }
    }

    static Async__c workItem(
        String apexClass,
        Id recordId,
        String status,
        Id threadId
    ) {
        Async__c workItem = new Async__c(
            Apex__c = apexClass,
            Record_Id__c = String.valueOf(recordId),
            Status__c = status
        );
        workItem.put('Thread__c', threadId);
        return workItem;
    }

    static List<List<SObject>> insertBatchesFor(
        DMLMock dmlMock,
        Schema.SObjectType sObjectType
    ) {
        List<List<SObject>> matchingBatches = new List<List<SObject>>();
        for (List<SObject> batch : dmlMock.inserts) {
            if (!batch.isEmpty() && batch[0].getSObjectType() == sObjectType) {
                matchingBatches.add(batch);
            }
        }
        return matchingBatches;
    }

    public with sharing class SpyJobService extends Async.JobService {
        public Integer enqueueNextJobCalls = 0;
        public Integer startThreadCalls = 0;
        public Integer lastEnqueueFailures = -1;
        public Integer lastStartFailures = -1;
        public Id lastThreadId;

        public override void enqueueNextJob(Integer failures) {
            this.enqueueNextJobCalls++;
            this.lastEnqueueFailures = failures;
        }

        public override void enqueueNextJob(Id threadId, Integer failures) {
            this.enqueueNextJobCalls++;
            this.lastThreadId = threadId;
            this.lastEnqueueFailures = failures;
        }

        public override void enqueueNextJob(
            Id threadId,
            Integer failures,
            String runKey
        ) {
            this.enqueueNextJobCalls++;
            this.lastThreadId = threadId;
            this.lastEnqueueFailures = failures;
        }

        public override void startThread(Integer failures) {
            this.startThreadCalls++;
            this.lastStartFailures = failures;
        }
    }

    public with sharing class MyTestAsync extends Async {
        public override void execute(Set<Id> ids) {
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName
                FROM Contact
                WHERE Id IN :ids
            ];
            for (Contact contact : contacts) {
                contact.FirstName = 'Hello';
            }
            update contacts;
        }
    }

    public with sharing class SetupSafeParentAsync extends Async {
        public override void execute(Set<Id> ids) {
            String suffix = String.valueOf(Crypto.getRandomInteger())
                .replace('-', '0');
            DML.insertRecords(
                new List<SObject>{
                    new Group(
                        Name = 'Async Setup Safe ' + suffix,
                        DeveloperName = 'Async_Setup_Safe_' + suffix,
                        Type = 'Regular'
                    )
                }
            );

            Async.enqueue(SetupSafeChildAsync.class, ids);
            Async.enqueue(SetupSafeChildAsync.class, ids);
        }
    }

    public with sharing class SetupSafeStagedParentAsync extends Async {
        public override void execute(Set<Id> ids) {
            String suffix = String.valueOf(Crypto.getRandomInteger())
                .replace('-', '0');
            DML.insertRecords(
                new List<SObject>{
                    new Group(
                        Name = 'Async Staged Setup Safe ' + suffix,
                        DeveloperName = 'Async_Staged_Setup_Safe_' + suffix,
                        Type = 'Regular'
                    )
                }
            );

            Async.stage(SetupSafeChildAsync.class, ids);
            Async.stage(SetupSafeChildAsync.class, ids);
            Async.flush();
        }
    }

    public with sharing class SetupSafeChildAsync extends Async {
        public override void execute(Set<Id> ids) {
            List<Contact> contacts = [
                SELECT Id, FirstName
                FROM Contact
                WHERE Id IN :ids
            ];
            for (Contact contact : contacts) {
                contact.FirstName = 'Child';
            }
            update contacts;
        }
    }

    public with sharing class PartialResultAsync extends Async {
        public override void execute(Set<Id> ids) {
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName
                FROM Contact
                WHERE Id IN :ids
                ORDER BY LastName ASC
            ];
            List<Contact> contactsToUpdate = new List<Contact>();
            for (Contact contact : contacts) {
                if (contact.LastName == 'A Explicit Complete') {
                    complete(contact.Id);
                    contact.FirstName = 'Explicit';
                    contactsToUpdate.add(contact);
                } else if (contact.LastName == 'B Explicit Fail') {
                    fail(contact.Id, 'partial failure');
                } else {
                    contact.FirstName = 'Default';
                    contactsToUpdate.add(contact);
                }
            }
            update contactsToUpdate;
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
