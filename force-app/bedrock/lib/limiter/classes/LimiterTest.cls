/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:Limiter')
public with sharing class LimiterTest {
    @istest
    static void testGetLimits_returnsTransactionAndPlatformLimitsByName() {
        Map<String, Limiter.LimitUsage> limits = Limiter.getLimits();

        Assert.isNotNull(
            limits.get(Limiter.key(Limiter.types.QUEUEABLE_JOBS)),
            'Expected transaction queueable usage to be available by name.'
        );
        Assert.isNotNull(
            limits.get(Limiter.key(Limiter.types.SOQL_QUERIES)),
            'Expected transaction SOQL usage to be available by name.'
        );
        Assert.isNotNull(
            limits.get(Limiter.key(Limiter.types.CPU_TIME)),
            'Expected transaction CPU usage to be available by name.'
        );
        Assert.isNotNull(
            limits.get(Limiter.key(Limiter.types.HEAP_SIZE)),
            'Expected transaction heap usage to be available by name.'
        );
        Assert.isNotNull(
            limits.get(Limiter.key(Limiter.types.DML_STATEMENTS)),
            'Expected transaction DML usage to be available by name.'
        );
        Assert.isTrue(
            limits.size() > 5,
            'Expected org/platform limits to be included with transaction limits.'
        );
    }

    @istest
    static void testGetLimit_returnsSpecificLimitByName() {
        Limiter.setMock(
            new LimiterMock()
                .setLimit(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS, 25, 100)
        );

        Limiter.LimitUsage limitUsage = Limiter.getLimit(
            Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS
        );

        Assert.areEqual(
            'DailyAsyncApexExecutions',
            limitUsage.name,
            'Expected the requested limit name to be preserved.'
        );
        Assert.areEqual(
            25,
            limitUsage.used,
            'Expected the requested limit to expose the used amount.'
        );
        Assert.areEqual(
            100,
            limitUsage.allowed,
            'Expected the requested limit to expose the allowed amount.'
        );
        Assert.areEqual(
            75,
            limitUsage.remaining,
            'Expected the requested limit to expose remaining capacity.'
        );
        Assert.areEqual(
            0.25,
            limitUsage.ratio,
            'Expected the requested limit to expose used divided by allowed.'
        );
    }

    @istest
    static void testGetLimit_returnsNullWhenLimitIsMissing() {
        Limiter.setMock(new LimiterMock());

        Assert.areEqual(
            null,
            Limiter.getLimit('NoSuchLimit'),
            'Expected a missing limit name to return null.'
        );
    }

    @istest
    static void testIsSafe_usesDefaultThresholdForSpecificLimit() {
        Limiter.setMock(
            new LimiterMock()
                .setLimit(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS, 89, 100)
        );

        Assert.isTrue(
            Limiter.isSafe(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS),
            'Expected a specific limit below the default threshold to be safe.'
        );
    }

    @istest
    static void testIsSafe_returnsFalseWhenSpecificLimitReachesDefaultThreshold() {
        Limiter.setMock(
            new LimiterMock()
                .setLimit(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS, 90, 100)
        );

        Assert.isFalse(
            Limiter.isSafe(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS),
            'Expected a specific limit at the default threshold to be unsafe.'
        );
    }

    @istest
    static void testIsSafe_acceptsCallerProvidedThreshold() {
        Limiter.setMock(
            new LimiterMock()
                .setLimit(
                    Limiter.types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS,
                    75,
                    100
                )
        );

        Assert.isTrue(
            Limiter.isSafe(
                Limiter.types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS,
                80
            ),
            'Expected a specific limit below the caller threshold to be safe.'
        );
        Assert.isFalse(
            Limiter.isSafe(
                Limiter.types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS,
                75
            ),
            'Expected a specific limit at the caller threshold to be unsafe.'
        );
    }

    @istest
    static void testIsSafe_returnsFalseWhenSpecificLimitNameIsMissing() {
        Limiter.setMock(new LimiterMock());

        Assert.isFalse(
            Limiter.isSafe('NoSuchLimit', 90),
            'Expected an unknown limit name to be unsafe so framework integrations catch bad limit names.'
        );
    }
}
