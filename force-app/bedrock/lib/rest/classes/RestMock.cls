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
