/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:RestConsoleController')
private class RestConsoleControllerTest {
  @istest
  static void testGetState_returnsRoutesSettingsAndMetrics() {
    RestConsoleController.setQueryService(
      new QueryServiceMock()
        .setting(
          new Rest_Settings__c(
            Unknown_Route_Status_Code__c = 410,
            Inactive_Route_Status_Code__c = 451,
            Unsupported_Method_Status_Code__c = 409,
            Access_Denied_Status_Code__c = 401,
            Expose_Error_Details__c = true
          )
        )
        .config(
          config('accounts_v2', true, false, 'accounts', 2, 'AccountRest')
        )
        .config(config('accounts_v1', true, true, 'accounts', 1, 'AccountRest'))
        .config(config('orders_v1', false, 'orders', 1, 'OrderRest'))
        .restClass(apexClass('AccountRest'))
    );

    Test.startTest();
    RestConsoleController.ConsoleState state = RestConsoleController.getState();
    Test.stopTest();

    Assert.areEqual(
      3,
      state.routeCount,
      'Expected console state to count all REST route configs.'
    );
    Assert.areEqual(
      2,
      state.activeRouteCount,
      'Expected console state to count active REST route configs.'
    );
    Assert.areEqual(
      1,
      state.inactiveRouteCount,
      'Expected console state to count inactive REST route configs.'
    );
    Assert.areEqual(
      2,
      state.versionedRouteCount,
      'Expected console state to count unique configured versions.'
    );
    Assert.areEqual(
      410,
      state.settings.effectiveUnknownRouteStatusCode,
      'Expected settings row to expose configured unknown-route status.'
    );
    Assert.areEqual(
      451,
      state.settings.effectiveInactiveRouteStatusCode,
      'Expected settings row to expose configured inactive-route status.'
    );
    Assert.areEqual(
      409,
      state.settings.effectiveUnsupportedMethodStatusCode,
      'Expected settings row to expose configured unsupported-method status.'
    );
    Assert.areEqual(
      401,
      state.settings.effectiveAccessDeniedStatusCode,
      'Expected settings row to expose configured access-denied status.'
    );
    Assert.isTrue(
      state.settings.exposeErrorDetails,
      'Expected settings row to expose the error-detail toggle.'
    );
    Assert.areEqual(
      '/services/apexrest/api/v2/accounts',
      state.routes[0].endpointUrl,
      'Expected route rows to expose versioned endpoint URLs.'
    );
    Assert.isFalse(
      state.routes[0].isDefaultVersion,
      'Expected non-default route rows to expose default-version state.'
    );
    Assert.isTrue(
      state.routes[1].isDefaultVersion,
      'Expected default route rows to expose default-version state.'
    );
    Assert.areEqual(
      1,
      state.restClasses.size(),
      'Expected console state to include available Rest subclasses.'
    );
    Assert.areEqual(
      'AccountRest',
      state.restClasses[0].value,
      'Expected Rest class options to expose class names as values.'
    );
  }

  @istest
  static void testIsRestClass_detectsRestSubclasses() {
    Assert.isTrue(
      RestConsoleController.isRestClass(
        'public with sharing class AccountRest extends Rest { }'
      ),
      'Expected class bodies that extend Rest to be detected.'
    );
    Assert.isTrue(
      RestConsoleController.isRestClass(
        'public with sharing class AccountRest extends Rest{ }'
      ),
      'Expected class bodies with compact extends syntax to be detected.'
    );
    Assert.isFalse(
      RestConsoleController.isRestClass(
        'public with sharing class AccountService { }'
      ),
      'Expected unrelated Apex classes not to be listed as Rest endpoints.'
    );
  }

  @istest
  static void testSaveSettings_createsOrganizationSettings() {
    Test.startTest();
    RestConsoleController.ConsoleState state = RestConsoleController.saveSettings(
      404,
      404,
      405,
      403,
      true
    );
    Test.stopTest();

    Rest_Settings__c settings = [
      SELECT
        SetupOwnerId,
        Unknown_Route_Status_Code__c,
        Inactive_Route_Status_Code__c,
        Unsupported_Method_Status_Code__c,
        Access_Denied_Status_Code__c,
        Expose_Error_Details__c
      FROM Rest_Settings__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      LIMIT 1
    ];
    Assert.areEqual(
      UserInfo.getOrganizationId(),
      settings.SetupOwnerId,
      'Expected saveSettings to create organization-owned REST settings.'
    );
    Assert.areEqual(
      404,
      settings.Unknown_Route_Status_Code__c,
      'Expected saveSettings to persist unknown-route status.'
    );
    Assert.areEqual(
      404,
      settings.Inactive_Route_Status_Code__c,
      'Expected saveSettings to persist inactive-route status.'
    );
    Assert.areEqual(
      405,
      settings.Unsupported_Method_Status_Code__c,
      'Expected saveSettings to persist unsupported-method status.'
    );
    Assert.areEqual(
      403,
      settings.Access_Denied_Status_Code__c,
      'Expected saveSettings to persist access-denied status.'
    );
    Assert.isTrue(
      settings.Expose_Error_Details__c,
      'Expected saveSettings to persist expose-error-details.'
    );
    Assert.isTrue(
      state.settings.hasRecord,
      'Expected refreshed state to include the saved settings row.'
    );
  }

  @istest
  static void testCreateEndpoint_enqueuesCustomMetadataDeployment() {
    DeployServiceMock deployments = new DeployServiceMock();
    RestConsoleController.setDeployService(deployments);

    Test.startTest();
    RestConsoleController.EndpointCreationResult result = RestConsoleController.createEndpoint(
      null,
      'Accounts V1',
      '/accounts/',
      1,
      'AccountRest',
      true,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      '0Af000000000001AAA',
      result.deploymentJobId,
      'Expected createEndpoint to return the metadata deployment job id.'
    );
    Assert.areEqual(
      'Rest_Config__mdt.accounts_v1',
      result.fullName,
      'Expected createEndpoint to derive a stable metadata full name.'
    );
    Assert.areEqual(
      '/services/apexrest/api/v1/accounts',
      result.endpointUrl,
      'Expected createEndpoint to return the versioned endpoint URL.'
    );
    Assert.areEqual(
      'Rest_Config__mdt.accounts_v1',
      deployments.config.fullName,
      'Expected createEndpoint to enqueue a Rest_Config__mdt record.'
    );
    Assert.areEqual(
      'Accounts V1',
      deployments.config.label,
      'Expected createEndpoint to preserve the provided metadata label.'
    );
    Assert.areEqual(
      'accounts',
      valueFor(deployments.config, 'Route__c'),
      'Expected createEndpoint to normalize root routes.'
    );
    Assert.areEqual(
      1,
      valueFor(deployments.config, 'Version__c'),
      'Expected createEndpoint to set the requested version.'
    );
    Assert.areEqual(
      'AccountRest',
      valueFor(deployments.config, 'Apex__c'),
      'Expected createEndpoint to set the requested Apex class.'
    );
    Assert.areEqual(
      true,
      valueFor(deployments.config, 'Active__c'),
      'Expected createEndpoint to set active by default.'
    );
    Assert.areEqual(
      true,
      valueFor(deployments.config, 'Default__c'),
      'Expected createEndpoint to set the requested default-version flag.'
    );
  }

  static Rest_Config__mdt config(
    String developerName,
    Boolean active,
    String route,
    Integer version,
    String apexClass
  ) {
    return config(developerName, active, false, route, version, apexClass);
  }

  static Rest_Config__mdt config(
    String developerName,
    Boolean active,
    Boolean defaultVersion,
    String route,
    Integer version,
    String apexClass
  ) {
    Rest_Config__mdt config = new Rest_Config__mdt();
    config.DeveloperName = developerName;
    config.MasterLabel = developerName.replace('_', ' ');
    config.Active__c = active;
    config.Default__c = defaultVersion;
    config.Route__c = route;
    config.Version__c = version;
    config.Apex__c = apexClass;
    return config;
  }

  static ApexClass apexClass(String name) {
    ApexClass apexClass = new ApexClass();
    apexClass.Name = name;
    return apexClass;
  }

  static Object valueFor(Metadata.CustomMetadata config, String fieldName) {
    for (Metadata.CustomMetadataValue value : config.values) {
      if (value.field == fieldName)
        return value.value;
    }
    return null;
  }

  class QueryServiceMock extends RestConsoleController.QueryService {
    List<Rest_Config__mdt> configs = new List<Rest_Config__mdt>();
    List<ApexClass> restClasses = new List<ApexClass>();
    Rest_Settings__c settings;

    QueryServiceMock config(Rest_Config__mdt config) {
      configs.add(config);
      return this;
    }

    QueryServiceMock restClass(ApexClass apexClass) {
      restClasses.add(apexClass);
      return this;
    }

    QueryServiceMock setting(Rest_Settings__c settings) {
      this.settings = settings;
      return this;
    }

    public override List<Rest_Config__mdt> getConfigs() {
      return configs;
    }

    public override Rest_Settings__c getOrganizationSettings() {
      return settings;
    }

    public override List<ApexClass> getRestClasses() {
      return restClasses;
    }
  }

  class DeployServiceMock extends RestConsoleController.DeployService {
    Metadata.CustomMetadata config;

    public override String enqueue(Metadata.CustomMetadata config) {
      this.config = config;
      return '0Af000000000001AAA';
    }
  }
}
