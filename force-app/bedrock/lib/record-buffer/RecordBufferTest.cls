/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:RecordBuffer')
private class RecordBufferTest {
    static DMLMock setupDmlMock() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        return dmlMock;
    }

    @istest
    static void testFlushUpsertsBasicInsertAndBasicUpdate() {
        DMLMock dmlMock = setupDmlMock();

        Account account = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock')
            .build()[0];

        Contact contact = (Contact) new TestData(Contact.sObjectType)
            .put(Contact.LastName, 'Lovelace')
            .mockIds()
            .build()[0];

        RecordBuffer.start();
        RecordBuffer.put(account);
        RecordBuffer.put(contact);
        RecordBuffer.flush();

        Assert.areEqual(
            2,
            dmlMock.upserts.size(),
            'Expected flush() to issue one upsert call per object type staged in the buffer.'
        );
        Assert.areEqual(
            1,
            dmlMock.upserts[0].size(),
            'Expected the first upsert call to contain exactly one staged record.'
        );
        Assert.areEqual(
            1,
            dmlMock.upserts[1].size(),
            'Expected the second upsert call to contain exactly one staged record.'
        );
    }

    @istest
    static void testPutNullInputsAreIgnored() {
        DMLMock dmlMock = setupDmlMock();

        RecordBuffer.start();
        RecordBuffer.put((SObject) null);
        RecordBuffer.put((List<SObject>) null);
        RecordBuffer.put((Map<Id, SObject>) null);
        RecordBuffer.flush();

        Assert.areEqual(
            0,
            dmlMock.upserts.size(),
            'Expected null put() inputs to stage no records and produce no DML calls.'
        );
    }

    @istest
    static void testPutListWithNullElementStagesOnlyRealRecords() {
        DMLMock dmlMock = setupDmlMock();
        Account account = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Only Real Record')
            .build()[0];

        RecordBuffer.start();
        RecordBuffer.put(new List<SObject>{ null, account });
        RecordBuffer.flush();

        Assert.areEqual(
            1,
            dmlMock.upserts.size(),
            'Expected one upsert call when one non-null record is staged.'
        );
        Assert.areEqual(
            1,
            dmlMock.upserts[0].size(),
            'Expected only the non-null list member to be staged.'
        );
        Assert.areEqual(
            'Only Real Record',
            ((Account) dmlMock.upserts[0][0]).Name,
            'Expected the staged account values to be preserved.'
        );
    }

    @istest
    static void testFlushDedupesUpdatesById() {
        DMLMock dmlMock = setupDmlMock();

        Account original = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Original')
            .mockIds()
            .build()[0];
        Account updated = (Account) original.clone(true, false, false, false);
        updated.Name = 'Latest';

        RecordBuffer.start();
        RecordBuffer.put(original);
        RecordBuffer.put(updated);
        RecordBuffer.flush();

        Assert.areEqual(
            1,
            dmlMock.upserts.size(),
            'Expected a single upsert call for one object type.'
        );
        Assert.areEqual(
            1,
            dmlMock.upserts[0].size(),
            'Expected only one record after deduping updates by record Id.'
        );
        Assert.areEqual(
            'Latest',
            ((Account) dmlMock.upserts[0][0]).Name,
            'Expected the latest staged update to win for duplicate Ids.'
        );
    }

    @istest
    static void testGetByIdReturnsStagedUpdate() {
        Account account = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Buffered Update')
            .mockIds()
            .build()[0];

        RecordBuffer.start();
        RecordBuffer.put(account);

        Account result = (Account) RecordBuffer.put(account.Id);

        Assert.areEqual(
            account.Id,
            result.Id,
            'Expected get(Id) to return the staged record for a known Id.'
        );
        Assert.areEqual(
            'Buffered Update',
            result.Name,
            'Expected get(Id) to return the staged field values for a known Id.'
        );
    }

    @istest
    static void testGetByIdReturnsSkeletonWhenNotStaged() {
        Account account = (Account) new TestData(Account.sObjectType)
            .mockIds()
            .build()[0];

        RecordBuffer.start();
        Account result = (Account) RecordBuffer.put(account.Id);

        Assert.areEqual(
            account.Id,
            result.Id,
            'Expected get(Id) to return a skeletal SObject initialized with the requested Id when not staged.'
        );
        Assert.areEqual(
            null,
            result.Name,
            'Expected an unstaged skeletal SObject to have no staged field values.'
        );
    }

    @istest
    static void testGetByIdAndSetHandleNullAndEmpty() {
        RecordBuffer.start();

        SObject byNullId = RecordBuffer.put((Id) null);
        List<SObject> byNullSet = RecordBuffer.get((Set<Id>) null);
        List<SObject> byEmptySet = RecordBuffer.get(new Set<Id>());

        Assert.areEqual(
            null,
            byNullId,
            'Expected get(Id) to return null for a null Id input.'
        );
        Assert.areEqual(
            null,
            byNullSet,
            'Expected get(Set<Id>) to return null for a null Id set.'
        );
        Assert.areEqual(
            null,
            byEmptySet,
            'Expected get(Set<Id>) to return null for an empty Id set.'
        );
    }

    @istest
    static void testAutoStartContextOnPutAndFlush() {
        DMLMock dmlMock = setupDmlMock();
        Account account = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Auto Start')
            .build()[0];

        RecordBuffer.put(account);
        RecordBuffer.flush();

        Assert.areEqual(
            1,
            dmlMock.upserts.size(),
            'Expected put() to lazily create a context when start() is not called first.'
        );
        Assert.areEqual(
            1,
            dmlMock.upserts[0].size(),
            'Expected flush() to process records staged in an auto-started context.'
        );
    }

    @istest
    static void testNestedContextsFlushTopFirst() {
        DMLMock dmlMock = setupDmlMock();
        Account outerRecord = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Outer')
            .build()[0];
        Account innerRecord = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Inner')
            .build()[0];

        RecordBuffer.start();
        RecordBuffer.put(outerRecord);
        RecordBuffer.start();
        RecordBuffer.put(innerRecord);

        RecordBuffer.flush();
        Assert.areEqual(
            1,
            dmlMock.upserts.size(),
            'Expected first flush() to process only the most recent context.'
        );
        Assert.areEqual(
            'Inner',
            ((Account) dmlMock.upserts[0][0]).Name,
            'Expected first flush() to process inner-context records first.'
        );

        RecordBuffer.flush();
        Assert.areEqual(
            2,
            dmlMock.upserts.size(),
            'Expected second flush() to process the outer context after inner context is removed.'
        );
        Assert.areEqual(
            'Outer',
            ((Account) dmlMock.upserts[1][0]).Name,
            'Expected second flush() to process outer-context records.'
        );
    }
}
