@istest(testFor='ApexClass:TestData')
private class TestDataTest {
    @istest static void testBuild_defaultCountAndFieldValue() {
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock')
            .build();

        Assert.areEqual(1, records.size(), 'Expected build() to create one record by default.');
        Account account = (Account) records[0];
        Assert.areEqual('Bedrock', account.Name, 'Expected put(Account.Name, ...) to populate the built record.');
        Assert.areEqual(null, account.Id, 'Expected records to have no Id when mockIds() is not used.');
    }

    @istest static void testBuild_countCreatesRequestedNumberOfRecords() {
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Counted')
            .count(3)
            .build();

        Assert.areEqual(3, records.size(), 'Expected count(3) to produce exactly three records.');
        Assert.areEqual('Counted', ((Account) records[2]).Name, 'Expected template field values to be applied to each generated record.');
    }

    @istest static void testBuild_mockIdsGeneratesKeyPrefixAndSequentialIds() {
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Mocked')
            .mockIds()
            .count(2)
            .build();

        Account first = (Account) records[0];
        Account second = (Account) records[1];
        String keyPrefix = Account.sObjectType.getDescribe().getKeyPrefix();
        String firstIdBase = String.valueOf(first.Id).substring(0, 15);
        String secondIdBase = String.valueOf(second.Id).substring(0, 15);

        Assert.isTrue(String.valueOf(first.Id).startsWith(keyPrefix), 'Expected first mock Id to use Account key prefix.');
        Assert.isTrue(String.valueOf(second.Id).startsWith(keyPrefix), 'Expected second mock Id to use Account key prefix.');
        Assert.areNotEqual(first.Id, second.Id, 'Expected each generated mock Id to be unique.');
        Assert.isTrue(firstIdBase.endsWith('1'), 'Expected first generated mock Id base value to end with sequence value 1.');
        Assert.isTrue(secondIdBase.endsWith('2'), 'Expected second generated mock Id base value to end with sequence value 2.');
    }

    @istest static void testBuild_sObjectValuePopulatesLookupAndRelationship() {
        Account parent = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Parent Account')
            .mockIds()
            .build()[0];

        Contact contact = (Contact) new TestData(Contact.sObjectType)
            .put(Contact.LastName, 'Child Contact')
            .put(Contact.AccountId, parent)
            .mockIds()
            .build()[0];

        Assert.areEqual(parent.Id, contact.AccountId, 'Expected SObject value input to populate the lookup Id field.');
        Assert.areEqual(parent.Id, contact.Account.Id, 'Expected SObject value input to also hydrate the relationship record Id.');
        Assert.areEqual('Parent Account', contact.Account.Name, 'Expected relationship hydration to preserve parent field values.');
    }

    @istest static void testIdService_tracksCountersPerSObjectType() {
        TestData.IdService idService = new TestData.IdService();

        Id accountIdOne = idService.get(Account.sObjectType);
        Id contactIdOne = idService.get(Contact.sObjectType);
        Id accountIdTwo = idService.get(Account.sObjectType);
        String accountIdOneBase = String.valueOf(accountIdOne).substring(0, 15);
        String contactIdOneBase = String.valueOf(contactIdOne).substring(0, 15);
        String accountIdTwoBase = String.valueOf(accountIdTwo).substring(0, 15);

        Assert.isTrue(
            String.valueOf(accountIdOne).startsWith(Account.sObjectType.getDescribe().getKeyPrefix()),
            'Expected Account Ids from IdService to use the Account key prefix.'
        );
        Assert.isTrue(
            String.valueOf(contactIdOne).startsWith(Contact.sObjectType.getDescribe().getKeyPrefix()),
            'Expected Contact Ids from IdService to use the Contact key prefix.'
        );
        Assert.isTrue(accountIdOneBase.endsWith('1'), 'Expected first Account Id base sequence to end with 1.');
        Assert.isTrue(accountIdTwoBase.endsWith('2'), 'Expected second Account Id base sequence to end with 2.');
        Assert.isTrue(contactIdOneBase.endsWith('1'), 'Expected Contact base sequence to start independently at 1.');
    }
}
