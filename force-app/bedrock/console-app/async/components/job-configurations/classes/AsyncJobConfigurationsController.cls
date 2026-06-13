public with sharing class AsyncJobConfigurationsController {
    @AuraEnabled
    public static List<JobConfigurationRow> getJobConfigurations() {
        List<JobConfigurationRow> rows = new List<JobConfigurationRow>();

        for (Async_Config__mdt config : [
            SELECT Id, DeveloperName, MasterLabel, Apex__c, Batch_Size__c
            FROM Async_Config__mdt
            WITH USER_MODE
            ORDER BY DeveloperName ASC
            LIMIT 500
        ]) {
            rows.add(new JobConfigurationRow(config));
        }

        return rows;
    }

    public class JobConfigurationRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String developerName;
        @AuraEnabled public String label;
        @AuraEnabled public String apexClass;
        @AuraEnabled public Decimal batchSize;

        public JobConfigurationRow(Async_Config__mdt config) {
            this.id = config.Id;
            this.developerName = config.DeveloperName;
            this.label = config.MasterLabel;
            this.apexClass = config.Apex__c;
            this.batchSize = config.Batch_Size__c;
        }
    }
}
