/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:Selector')
private class SelectorTest {
    @istest
    static void testQueryText_includesFieldsAndWhereClauses() {
        Selector selector = new AccountSelector(
            new Set<String>{ 'Name', 'Owner.Name' },
            new Set<String>{ 'Name LIKE \'Bedrock%\'' }
        );

        String queryText = selector.queryText(new Set<Id>());

        Assert.areEqual(
            'SELECT Id, Name, Owner.Name FROM Account WHERE Id IN :ids AND (Name LIKE \'Bedrock%\')',
            queryText,
            'Expected selector query text to include sorted fields, the Id filter, and custom where clauses.'
        );
    }

    @istest
    static void testKey_changesWhenFieldSetChanges() {
        Selector baseSelector = new AccountSelector(new Set<String>{ 'Name' });
        Selector expandedSelector = new AccountSelector(
            new Set<String>{ 'Name', 'Owner.Name' }
        );

        Assert.areNotEqual(
            baseSelector.key(),
            expandedSelector.key(),
            'Expected selector key to change when selected fields or relations change.'
        );
    }

    @istest
    static void testKey_changesWhenWhereClausesChange() {
        Selector activeSelector = new AccountSelector(
            new Set<String>{ 'Name' },
            new Set<String>{ 'IsDeleted = false' }
        );
        Selector namedSelector = new AccountSelector(
            new Set<String>{ 'Name' },
            new Set<String>{ 'Name LIKE \'Bedrock%\'' }
        );

        Assert.areNotEqual(
            activeSelector.key(),
            namedSelector.key(),
            'Expected selector key to change when where clauses change.'
        );
    }

    @istest
    static void testInstance_reusesSelectorWithSameKey() {
        Selector.clearInstances();

        Selector first = Selector.instance(
            new AccountOnceSelector(new Set<String>{ 'Name' })
        );
        Selector second = Selector.instance(
            new AccountOnceSelector(new Set<String>{ 'Name' })
        );

        Assert.areEqual(
            first,
            second,
            'Expected Selector.instance to return the existing transaction selector when the class and contract hash match.'
        );
    }

    @istest
    static void testOnce_recordsUsesTransactionCache() {
        Account account = new Account(Name = 'Bedrock Once');
        insert account;
        Selector.Once selector = new AccountOnceSelector(
            new Set<String>{ 'Name' }
        );

        Integer queriesBefore = Limits.getQueries();
        List<SObject> firstResult = selector.records(new Set<Id>{ account.Id });
        Integer queriesAfterFirstResult = Limits.getQueries();
        List<SObject> secondResult = selector.records(
            new Set<Id>{ account.Id }
        );

        Assert.areEqual(
            1,
            firstResult.size(),
            'Expected first selector call to return the inserted account.'
        );
        Assert.areEqual(
            'Bedrock Once',
            ((Account) firstResult[0]).Name,
            'Expected first selector call to hydrate selected account fields.'
        );
        Assert.areEqual(
            1,
            secondResult.size(),
            'Expected second selector call to return the cached account.'
        );
        Assert.areEqual(
            queriesBefore + 1,
            queriesAfterFirstResult,
            'Expected first selector call to query missing records.'
        );
        Assert.areEqual(
            queriesAfterFirstResult,
            Limits.getQueries(),
            'Expected second selector call for the same Id to avoid a repeat query.'
        );
    }

    @istest
    static void testQuery_ignoresSubscriberQueryMock() {
        Account account = new Account(Name = 'Bedrock Direct Query');
        insert account;
        Query.setMock(new QueryMock.Multiple());
        Selector selector = new AccountSelector(new Set<String>{ 'Name' });

        List<SObject> result = selector.records(new Set<Id>{ account.Id });

        Assert.areEqual(
            1,
            result.size(),
            'Selector should query real records without subscriber Query mocks.'
        );
        Assert.areEqual(
            'Bedrock Direct Query',
            ((Account) result[0]).Name,
            'Selector should hydrate selected fields from direct SOQL.'
        );
    }

    @istest
    static void testCached_recordsUsesPlatformCacheBeforeQuery() {
        Account account = (Account) new TestData(Account.sObjectType)
            .put(Account.Name, 'Bedrock Cached')
            .mockIds()
            .build()[0];
        PlatformCacheMock cacheMock = new PlatformCacheMock('SelectorTest');
        Selector.Cached selector = new AccountCachedSelector(
            new Set<String>{ 'Name' },
            cacheMock
        );
        cacheMock.valuesByKey.put(selector.cacheKey(account.Id), account);

        Integer queriesBefore = Limits.getQueries();
        List<SObject> result = selector.records(new Set<Id>{ account.Id });

        Assert.areEqual(
            1,
            result.size(),
            'Expected cached selector to return the Platform Cache record.'
        );
        Assert.areEqual(
            'Bedrock Cached',
            ((Account) result[0]).Name,
            'Expected cached selector to return the cached SObject payload.'
        );
        Assert.areEqual(
            queriesBefore,
            Limits.getQueries(),
            'Expected cached selector to avoid SOQL when Platform Cache contains the requested record.'
        );
        Assert.areEqual(
            new List<String>{ selector.cacheKey(account.Id) },
            cacheMock.gets,
            'Expected cached selector to read the Platform Cache key for the missing transaction record.'
        );
    }

    @istest
    static void testCached_recordsWritesPlatformCacheAfterQuery() {
        Account account = new Account(Name = 'Bedrock Cache Write');
        insert account;
        PlatformCacheMock cacheMock = new PlatformCacheMock('SelectorTest');
        Selector.Cached selector = new AccountCachedSelector(
            new Set<String>{ 'Name' },
            cacheMock
        );

        List<SObject> result = selector.records(new Set<Id>{ account.Id });

        Assert.areEqual(
            1,
            result.size(),
            'Expected cached selector to return the queried account.'
        );
        Assert.areEqual(
            new List<String>{ selector.cacheKey(account.Id) },
            cacheMock.puts,
            'Expected cached selector to write queried records to Platform Cache using the class and contract-hash key.'
        );
        Assert.areEqual(
            'Bedrock Cache Write',
            ((Account) cacheMock.valuesByKey.get(selector.cacheKey(account.Id)))
                .Name,
            'Expected cached selector to store the queried SObject payload in Platform Cache.'
        );
    }

    inherited sharing class AccountSelector extends Selector {
        AccountSelector(Set<String> fields) {
            super('Account', fields);
        }

        AccountSelector(Set<String> fields, Set<String> whereClauses) {
            super('Account', fields, whereClauses);
        }
    }

    inherited sharing class AccountOnceSelector extends Selector.Once {
        AccountOnceSelector(Set<String> fields) {
            super('Account', fields);
        }
    }

    inherited sharing class AccountCachedSelector extends Selector.Cached {
        AccountCachedSelector(Set<String> fields, PlatformCache cache) {
            super('Account', fields, cache);
        }
    }
}
