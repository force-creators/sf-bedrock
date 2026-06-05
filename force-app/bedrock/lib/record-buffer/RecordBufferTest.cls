@IsTest
private class RecordBufferTest {
    @IsTest
    static void flushUpsertsBasicInsertAndBasicUpdate() {
        DMLMock dmlMock = new DMLMock();
        DML.setMock(dmlMock);

        Account account = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock').build()[0];

        Contact contact = (Contact) new TestData(Contact.sObjectType)
            .put(Contact.LastName, 'Lovelace')
            .mockIds().build()[0];

        RecordBuffer.start();
        RecordBuffer.put(account);
        RecordBuffer.put(contact);
        RecordBuffer.flush();

        System.assertEquals(2, dmlMock.upserts.size(), 'Expected two upsert calls');
        System.assertEquals(1, dmlMock.upserts.get(0).size(), 'Expected first upsert call to contain one record');
        System.assertEquals(1, dmlMock.upserts.get(1).size(), 'Expected second upsert call to contain one record');
    }
}
