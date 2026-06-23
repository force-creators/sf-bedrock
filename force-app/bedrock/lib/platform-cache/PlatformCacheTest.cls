/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:PlatformCache')
private class PlatformCacheTest {
    private inherited sharing class ExampleOrgCache extends PlatformCache.Org {
        public ExampleOrgCache() {
            super('Bedrock');
        }
    }

    private inherited sharing class ExampleSessionCache extends PlatformCache.Session {
        public ExampleSessionCache() {
            super('Bedrock');
        }
    }

    private static PlatformCacheMock cacheMock() {
        PlatformCacheMock cacheMock = new PlatformCacheMock('Bedrock');
        PlatformCache.setMock(cacheMock);
        return cacheMock;
    }

    private static PlatformCacheMock sessionCacheMock() {
        PlatformCacheMock cacheMock = new PlatformCacheMock('Bedrock');
        PlatformCache.setSessionMock(cacheMock);
        return cacheMock;
    }

    @istest
    static void testOrg_put() {
        PlatformCacheMock cacheMock = cacheMock();

        new PlatformCache.Org('Bedrock').put('greeting', 'hello');

        Assert.areEqual(
            'hello',
            cacheMock.valuesByKey.get('greeting'),
            'Expected org cache put to store the value in the registered partition mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            cacheMock.puts,
            'Expected org cache put to record the written key on the registered partition mock.'
        );
        Assert.areEqual(
            0,
            cacheMock.gets.size(),
            'Expected org cache put to avoid any cache reads.'
        );
        Assert.areEqual(
            0,
            cacheMock.removes.size(),
            'Expected org cache put to avoid any cache removes.'
        );
    }

    @istest
    static void testOrg_get() {
        PlatformCacheMock cacheMock = cacheMock();
        cacheMock.valuesByKey.put('greeting', 'hello');

        Object value = new PlatformCache.Org('Bedrock').get('greeting');

        Assert.areEqual(
            'hello',
            value,
            'Expected org cache get to return the value from the registered partition mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            cacheMock.gets,
            'Expected org cache get to record the requested key on the registered partition mock.'
        );
        Assert.areEqual(
            0,
            cacheMock.puts.size(),
            'Expected org cache get to avoid any cache writes.'
        );
        Assert.areEqual(
            0,
            cacheMock.removes.size(),
            'Expected org cache get to avoid any cache removes.'
        );
    }

    @istest
    static void testOrg_remove() {
        PlatformCacheMock cacheMock = cacheMock();
        cacheMock.valuesByKey.put('greeting', 'hello');

        new PlatformCache.Org('Bedrock').remove('greeting');

        Assert.areEqual(
            null,
            cacheMock.valuesByKey.get('greeting'),
            'Expected org cache remove to delete the value from the registered partition mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            cacheMock.removes,
            'Expected org cache remove to record the removed key on the registered partition mock.'
        );
        Assert.areEqual(
            0,
            cacheMock.puts.size(),
            'Expected org cache remove to avoid any cache writes.'
        );
        Assert.areEqual(
            0,
            cacheMock.gets.size(),
            'Expected org cache remove to avoid any cache reads.'
        );
    }

    @istest
    static void testSession_get() {
        PlatformCacheMock cacheMock = sessionCacheMock();
        cacheMock.valuesByKey.put('greeting', 'hello');

        Object value = new PlatformCache.Session('Bedrock').get('greeting');

        Assert.areEqual(
            'hello',
            value,
            'Expected session cache get to return the value from the registered partition mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            cacheMock.gets,
            'Expected session cache get to record the requested key on the registered partition mock.'
        );
        Assert.areEqual(
            0,
            cacheMock.puts.size(),
            'Expected session cache get to avoid any cache writes.'
        );
        Assert.areEqual(
            0,
            cacheMock.removes.size(),
            'Expected session cache get to avoid any cache removes.'
        );
    }

    @istest
    static void testSession_put() {
        PlatformCacheMock cacheMock = sessionCacheMock();

        new PlatformCache.Session('Bedrock').put('greeting', 'hello');

        Assert.areEqual(
            'hello',
            cacheMock.valuesByKey.get('greeting'),
            'Expected session cache put to store the value in the registered partition mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            cacheMock.puts,
            'Expected session cache put to record the written key on the registered partition mock.'
        );
        Assert.areEqual(
            0,
            cacheMock.gets.size(),
            'Expected session cache put to avoid any cache reads.'
        );
        Assert.areEqual(
            0,
            cacheMock.removes.size(),
            'Expected session cache put to avoid any cache removes.'
        );
    }

    @istest
    static void testSession_remove() {
        PlatformCacheMock cacheMock = sessionCacheMock();
        cacheMock.valuesByKey.put('greeting', 'hello');

        new PlatformCache.Session('Bedrock').remove('greeting');

        Assert.areEqual(
            null,
            cacheMock.valuesByKey.get('greeting'),
            'Expected session cache remove to delete the value from the registered partition mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            cacheMock.removes,
            'Expected session cache remove to record the removed key on the registered partition mock.'
        );
        Assert.areEqual(
            0,
            cacheMock.puts.size(),
            'Expected session cache remove to avoid any cache writes.'
        );
        Assert.areEqual(
            0,
            cacheMock.gets.size(),
            'Expected session cache remove to avoid any cache reads.'
        );
    }

    @istest
    static void testSubclassOrg_get() {
        PlatformCacheMock cacheMock = cacheMock();
        cacheMock.valuesByKey.put('greeting', 'hello');

        Object value = new ExampleOrgCache().get('greeting');

        Assert.areEqual(
            'hello',
            value,
            'Expected a cache subclass extending PlatformCache.Org to return the value from the registered partition mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            cacheMock.gets,
            'Expected a cache subclass extending PlatformCache.Org to read through the registered partition mock.'
        );
    }

    @istest
    static void testSubclassSession_get() {
        PlatformCacheMock cacheMock = sessionCacheMock();
        cacheMock.valuesByKey.put('greeting', 'hello');

        Object value = new ExampleSessionCache().get('greeting');

        Assert.areEqual(
            'hello',
            value,
            'Expected a cache subclass extending PlatformCache.Session to return the value from the registered partition mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            cacheMock.gets,
            'Expected a cache subclass extending PlatformCache.Session to read through the registered partition mock.'
        );
    }

    @istest
    static void testMockRetainsConfiguredPartitionName() {
        PlatformCacheMock cacheMock = cacheMock();

        Assert.areEqual(
            'Bedrock',
            cacheMock.partitionName,
            'Expected the registered partition mock to retain its configured partition name.'
        );
    }

    @istest
    static void testOrgAndSessionMocksAreScopedSeparately() {
        PlatformCacheMock orgCacheMock = cacheMock();
        PlatformCacheMock sessionCacheMock = sessionCacheMock();
        orgCacheMock.valuesByKey.put('greeting', 'org hello');
        sessionCacheMock.valuesByKey.put('greeting', 'session hello');

        Object orgValue = new PlatformCache.Org('Bedrock').get('greeting');
        Object sessionValue = new ExampleSessionCache().get('greeting');

        Assert.areEqual(
            'org hello',
            orgValue,
            'Expected org cache reads to use the org-scoped mock for the partition.'
        );
        Assert.areEqual(
            'session hello',
            sessionValue,
            'Expected session cache reads to use the session-scoped mock for the partition.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            orgCacheMock.gets,
            'Expected org cache reads to be recorded only on the org-scoped mock.'
        );
        Assert.areEqual(
            new List<String>{ 'greeting' },
            sessionCacheMock.gets,
            'Expected session cache reads to be recorded only on the session-scoped mock.'
        );
    }
}
