/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public inherited sharing class FeatureFlag {
    static Map<String, Feature_Flag__mdt> flagsByName = new Map<String, Feature_Flag__mdt>();

    public static Boolean isEnabled(String name) {
        if (String.isBlank(name))
            return false;

        Feature_Flag__mdt flag = get(name);
        return flag != null && flag.Is_Enabled__c;
    }

    static Feature_Flag__mdt get(String name) {
        if (flagsByName.containsKey(name)) {
            return flagsByName.get(name);
        }

        List<Feature_Flag__mdt> flags = [
            SELECT Name__c, Is_Enabled__c
            FROM Feature_Flag__mdt
            WHERE Name__c = :name
            LIMIT 1
        ];

        Feature_Flag__mdt flag = flags.isEmpty() ? null : flags[0];
        flagsByName.put(name, flag);
        return flag;
    }

    @testvisible
    public static void set(String name, Boolean enabled) {
        flagsByName.put(
            name,
            new Feature_Flag__mdt(Name__c = name, Is_Enabled__c = enabled)
        );
    }

    @testvisible
    static void clearCache() {
        flagsByName.clear();
    }
}
