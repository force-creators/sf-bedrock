/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class EventRelayMetadataService {
    @testVisible
    List<Event_Config__mdt> configs;
    @testVisible
    Map<String, Event_Config__mdt> configByDeveloperName;

    public virtual List<Event_Config__mdt> getConfigs() {
        if (configs == null)
            configs = loadConfigs();
        return configs;
    }

    public virtual Event_Config__mdt getConfig(String developerName) {
        if (String.isBlank(developerName))
            return null;
        if (configByDeveloperName == null) {
            configByDeveloperName = new Map<String, Event_Config__mdt>();
            for (Event_Config__mdt config : getConfigs()) {
                configByDeveloperName.put(config.DeveloperName, config);
            }
        }
        return configByDeveloperName.get(developerName.trim());
    }

    public virtual Integer batchSize(String route, Integer defaultBatchSize) {
        Integer safeDefault = defaultBatchSize == null ||
            defaultBatchSize < 1
            ? EventRelay.settings.batchSize()
            : defaultBatchSize;
        Event_Config__mdt config = getConfig(route);
        if (
            config == null ||
            config.Batch_Size__c == null ||
            config.Batch_Size__c < 1
        )
            return safeDefault;
        return config.Batch_Size__c.intValue();
    }

    public virtual Integer maxRetries(String route) {
        Event_Config__mdt config = getConfig(route);
        if (
            config == null ||
            config.Max_Retries__c == null ||
            config.Max_Retries__c < 1
        )
            return 0;
        return config.Max_Retries__c.intValue();
    }

    protected virtual List<Event_Config__mdt> loadConfigs() {
        return (List<Event_Config__mdt>) Query.records(
            [
                SELECT
                    DeveloperName,
                    Active__c,
                    Direction__c,
                    Source_Type__c,
                    Routing_Key__c,
                    Routing_Value__c,
                    Apex__c,
                    Batch_Size__c,
                    Max_Retries__c,
                    Idempotency_Key_Path__c
                FROM Event_Config__mdt
                WHERE Active__c = TRUE
            ]
        );
    }
}
