/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class RestMock {
    public Rest.MetadataService metadata;
    public Rest.SettingsService settings;
    public Rest.Service service;

    public RestMock() {
        metadata = new Rest.MetadataService();
        settings = new Rest.SettingsService();
        service = new Rest.Service();
    }

    public RestMock seedConfigs(List<Rest_Config__mdt> configs) {
        metadata.setConfigs(configs);
        return this;
    }

    public RestMock seedSettings(Rest_Settings__c values) {
        settings.setSettings(values);
        return this;
    }
}
