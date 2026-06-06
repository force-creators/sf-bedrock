@istest(testFor='ApexClass:DML')
private class DMLTest {
    static DMLMock setupDmlMock() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);
        return dmlMock;
    }

    @istest static void testInsertRecords() {
        DMLMock dmlMock = setupDmlMock();
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock Insert')
            .count(2)
            .build();

        DML.insertRecords(records);

        Assert.areEqual(1, dmlMock.inserts.size(), 'Expected exactly one insert call to be captured by DMLMock.');
        Assert.areEqual(2, dmlMock.inserts[0].size(), 'Expected insert call to contain both provided records.');
        Assert.areEqual('Bedrock Insert', ((Account) dmlMock.inserts[0][0]).Name, 'Expected inserted account name to be preserved in the captured payload.');
        Assert.areEqual(0, dmlMock.updates.size(), 'Expected insert path to avoid update calls.');
        Assert.areEqual(0, dmlMock.upserts.size(), 'Expected insert path to avoid upsert calls.');
        Assert.areEqual(0, dmlMock.deletes.size(), 'Expected insert path to avoid delete calls.');
        Assert.areEqual(0, dmlMock.undeletes.size(), 'Expected insert path to avoid undelete calls.');
    }

    @istest static void testUpdateRecords() {
        DMLMock dmlMock = setupDmlMock();
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock Update')
            .mockIds()
            .count(2)
            .build();

        DML.updateRecords(records);

        Assert.areEqual(1, dmlMock.updates.size(), 'Expected exactly one update call to be captured by DMLMock.');
        Assert.areEqual(2, dmlMock.updates[0].size(), 'Expected update call to contain both provided records.');
        Assert.areEqual('Bedrock Update', ((Account) dmlMock.updates[0][1]).Name, 'Expected updated account name to be preserved in the captured payload.');
        Assert.areEqual(0, dmlMock.inserts.size(), 'Expected update path to avoid insert calls.');
        Assert.areEqual(0, dmlMock.upserts.size(), 'Expected update path to avoid upsert calls.');
        Assert.areEqual(0, dmlMock.deletes.size(), 'Expected update path to avoid delete calls.');
        Assert.areEqual(0, dmlMock.undeletes.size(), 'Expected update path to avoid undelete calls.');
    }

    @istest static void testUpsertRecords() {
        DMLMock dmlMock = setupDmlMock();
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock Upsert')
            .mockIds()
            .count(2)
            .build();

        DML.upsertRecords(records);

        Assert.areEqual(1, dmlMock.upserts.size(), 'Expected exactly one upsert call to be captured by DMLMock.');
        Assert.areEqual(2, dmlMock.upserts[0].size(), 'Expected upsert call to contain both provided records.');
        Assert.areEqual('Bedrock Upsert', ((Account) dmlMock.upserts[0][0]).Name, 'Expected upserted account name to be preserved in the captured payload.');
        Assert.areEqual(0, dmlMock.inserts.size(), 'Expected upsert path to avoid insert calls.');
        Assert.areEqual(0, dmlMock.updates.size(), 'Expected upsert path to avoid update calls.');
        Assert.areEqual(0, dmlMock.deletes.size(), 'Expected upsert path to avoid delete calls.');
        Assert.areEqual(0, dmlMock.undeletes.size(), 'Expected upsert path to avoid undelete calls.');
    }

    @istest static void testUpsertRecordsWithExternalId() {
        DMLMock dmlMock = setupDmlMock();
        List<SObject> records = new TestData(Contact.sObjectType)
            .put(Contact.LastName, 'External')
            .put(Contact.Email, 'external@example.com')
            .count(2)
            .build();

        DML.upsertRecords(records, Contact.Email);

        Assert.areEqual(1, dmlMock.upserts.size(), 'Expected exactly one external-id upsert call to be captured by DMLMock.');
        Assert.areEqual(2, dmlMock.upserts[0].size(), 'Expected external-id upsert call to contain both provided records.');
        Assert.areEqual('external@example.com', ((Contact) dmlMock.upserts[0][0]).Email, 'Expected external-id field value to be preserved in the captured payload.');
        Assert.areEqual(0, dmlMock.inserts.size(), 'Expected external-id upsert path to avoid insert calls.');
        Assert.areEqual(0, dmlMock.updates.size(), 'Expected external-id upsert path to avoid update calls.');
        Assert.areEqual(0, dmlMock.deletes.size(), 'Expected external-id upsert path to avoid delete calls.');
        Assert.areEqual(0, dmlMock.undeletes.size(), 'Expected external-id upsert path to avoid undelete calls.');
    }

    @istest static void testDeleteRecords() {
        DMLMock dmlMock = setupDmlMock();
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock Delete')
            .mockIds()
            .count(2)
            .build();

        DML.deleteRecords(records);

        Assert.areEqual(1, dmlMock.deletes.size(), 'Expected exactly one delete call to be captured by DMLMock.');
        Assert.areEqual(2, dmlMock.deletes[0].size(), 'Expected delete call to contain both provided records.');
        Assert.areEqual('Bedrock Delete', ((Account) dmlMock.deletes[0][0]).Name, 'Expected deleted account name to be preserved in the captured payload.');
        Assert.areEqual(0, dmlMock.inserts.size(), 'Expected delete path to avoid insert calls.');
        Assert.areEqual(0, dmlMock.updates.size(), 'Expected delete path to avoid update calls.');
        Assert.areEqual(0, dmlMock.upserts.size(), 'Expected delete path to avoid upsert calls.');
        Assert.areEqual(0, dmlMock.undeletes.size(), 'Expected delete path to avoid undelete calls.');
    }

    @istest static void testUndeleteRecords() {
        DMLMock dmlMock = setupDmlMock();
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock Undelete')
            .mockIds()
            .count(2)
            .build();

        DML.undeleteRecords(records);

        Assert.areEqual(1, dmlMock.undeletes.size(), 'Expected exactly one undelete call to be captured by DMLMock.');
        Assert.areEqual(2, dmlMock.undeletes[0].size(), 'Expected undelete call to contain both provided records.');
        Assert.areEqual('Bedrock Undelete', ((Account) dmlMock.undeletes[0][1]).Name, 'Expected undeleted account name to be preserved in the captured payload.');
        Assert.areEqual(0, dmlMock.inserts.size(), 'Expected undelete path to avoid insert calls.');
        Assert.areEqual(0, dmlMock.updates.size(), 'Expected undelete path to avoid update calls.');
        Assert.areEqual(0, dmlMock.upserts.size(), 'Expected undelete path to avoid upsert calls.');
        Assert.areEqual(0, dmlMock.deletes.size(), 'Expected undelete path to avoid delete calls.');
    }
}
