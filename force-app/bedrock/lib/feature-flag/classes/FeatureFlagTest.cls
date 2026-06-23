/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:FeatureFlag')
private class FeatureFlagTest {
    @istest
    static void testIsEnabled_returnsFalseWhenMissing() {
        Test.startTest();
        Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.missing');
        Test.stopTest();

        Assert.areEqual(
            false,
            enabled,
            'Expected a missing feature flag to fail closed as disabled.'
        );
    }

    @istest
    static void testSet_overridesMissingFlag() {
        FeatureFlag.set('bedrock.feature.missing', true);

        Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.missing');

        Assert.areEqual(
            true,
            enabled,
            'Expected set to allow tests to enable a missing feature flag.'
        );
    }

    @istest
    static void testSet_supportsFalseOverrides() {
        FeatureFlag.set('bedrock.feature.false', false);

        Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.false');

        Assert.areEqual(
            false,
            enabled,
            'Expected set to allow tests to explicitly disable a feature flag.'
        );
    }

    @istest
    static void testSet_nullClearsOverride() {
        FeatureFlag.set('bedrock.feature.override', true);
        FeatureFlag.set('bedrock.feature.override', null);

        Test.startTest();
        Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.override');
        Test.stopTest();

        Assert.areEqual(
            false,
            enabled,
            'Expected clearing a test override to restore the missing-flag default of false.'
        );
    }

    @istest
    static void testClearCache_removesCachedValues() {
        FeatureFlag.set('bedrock.feature.cached', true);

        Boolean overridden = FeatureFlag.isEnabled('bedrock.feature.cached');
        FeatureFlag.clearCache();

        Test.startTest();
        Boolean restored = FeatureFlag.isEnabled('bedrock.feature.cached');
        Test.stopTest();

        Assert.areEqual(
            true,
            overridden,
            'Expected set to change the cached feature flag value for the current transaction.'
        );
        Assert.areEqual(
            false,
            restored,
            'Expected clearCache to remove cached values so the next read falls back to the default disabled state.'
        );
    }

    @istest
    static void testIsEnabled_returnsFalseWhenNameBlank() {
        Assert.areEqual(
            false,
            FeatureFlag.isEnabled(null),
            'Expected a null feature flag name to return false.'
        );
        Assert.areEqual(
            false,
            FeatureFlag.isEnabled(''),
            'Expected an empty feature flag name to return false.'
        );
        Assert.areEqual(
            false,
            FeatureFlag.isEnabled('   '),
            'Expected a blank feature flag name to return false.'
        );
    }
}
