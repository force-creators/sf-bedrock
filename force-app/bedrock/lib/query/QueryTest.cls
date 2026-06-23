/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:Query')
private class QueryTest {
    @istest
    static void testRecords_returnsInputWhenNoMockSet() {
        List<SObject> records = new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock Query')
            .count(2)
            .build();

        List<SObject> result = Query.records(records);

        Assert.areEqual(
            2,
            result.size(),
            'Expected records() to return all provided records when using the default Query implementation.'
        );
        Assert.areEqual(
            'Bedrock Query',
            ((Account) result[0]).Name,
            'Expected records() to preserve values from the input payload.'
        );
        Assert.areEqual(
            records,
            result,
            'Expected default Query implementation to pass through the same list instance.'
        );
    }

    @istest
    static void testRecords_usesMockWhenSet() {
        List<SObject> inputRecords = new TestData(Account.sObjectType)
            .put(Account.Name, 'Input')
            .count(1)
            .build();
        List<SObject> mockRecords = new TestData(Account.sObjectType)
            .put(Account.Name, 'Mocked')
            .count(2)
            .build();

        Query.setMock(new QueryMock(mockRecords));

        List<SObject> result = Query.records(inputRecords);

        Assert.areEqual(
            2,
            result.size(),
            'Expected records() to return the Query mock result instead of the input list.'
        );
        Assert.areEqual(
            'Mocked',
            ((Account) result[0]).Name,
            'Expected records() to return records provided by QueryMock.'
        );
        Assert.areEqual(
            mockRecords,
            result,
            'Expected records() to return the exact list supplied by QueryMock.'
        );
    }
}
