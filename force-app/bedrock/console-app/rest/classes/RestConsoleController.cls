/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class RestConsoleController {
  static final Integer REFRESH_INTERVAL_SECONDS = 15;
  @testVisible
  static QueryService queries = new QueryService();
  @testVisible
  static DeployService deployments = new DeployService();

  @testVisible
  static void setQueryService(QueryService queryService) {
    queries = queryService;
  }

  @testVisible
  static void setDeployService(DeployService deployService) {
    deployments = deployService;
  }

  @testVisible
  static void reset() {
    queries = new QueryService();
    deployments = new DeployService();
  }

  @AuraEnabled
  public static ConsoleState getState() {
    List<Rest_Config__mdt> configs = queries.getConfigs();
    Rest_Settings__c settings = queries.getOrganizationSettings();
    List<ApexClass> restClasses = queries.getRestClasses();

    ConsoleState state = new ConsoleState();
    state.generatedAt = System.now();
    state.refreshIntervalSeconds = REFRESH_INTERVAL_SECONDS;
    state.settings = new SettingsRow(settings);
    state.restClasses = restClassOptions(restClasses);

    for (Rest_Config__mdt config : configs) {
      RouteRow row = new RouteRow(config);
      state.routes.add(row);
      if (row.isActive) {
        state.activeRouteCount++;
      } else {
        state.inactiveRouteCount++;
      }
      if (row.version != null)
        state.versionCount.add(row.version);
    }

    state.routeCount = state.routes.size();
    state.versionedRouteCount = state.versionCount.size();
    return state;
  }

  @AuraEnabled
  public static ConsoleState saveSettings(
    Decimal unknownRouteStatusCode,
    Decimal inactiveRouteStatusCode,
    Decimal unsupportedMethodStatusCode,
    Decimal accessDeniedStatusCode,
    Boolean exposeErrorDetails
  ) {
    validateStatusCode(unknownRouteStatusCode, 'Unknown route status code');
    validateStatusCode(inactiveRouteStatusCode, 'Inactive route status code');
    validateStatusCode(
      unsupportedMethodStatusCode,
      'Unsupported method status code'
    );
    validateStatusCode(accessDeniedStatusCode, 'Access denied status code');

    Rest_Settings__c existingSettings = queries.getOrganizationSettings();
    Rest_Settings__c settings = existingSettings == null
      ? new Rest_Settings__c(SetupOwnerId = UserInfo.getOrganizationId())
      : new Rest_Settings__c(Id = existingSettings.Id);
    settings.Unknown_Route_Status_Code__c = unknownRouteStatusCode;
    settings.Inactive_Route_Status_Code__c = inactiveRouteStatusCode;
    settings.Unsupported_Method_Status_Code__c = unsupportedMethodStatusCode;
    settings.Access_Denied_Status_Code__c = accessDeniedStatusCode;
    settings.Expose_Error_Details__c = exposeErrorDetails == true;

    saveSettingsRecord(settings, existingSettings == null);
    return getState();
  }

  @AuraEnabled
  public static EndpointCreationResult createEndpoint(
    String developerName,
    String label,
    String route,
    Decimal version,
    String apexClass,
    Boolean active,
    Boolean defaultVersion
  ) {
    String safeRoute = normalizeRoute(route);
    Decimal safeVersion = validateVersion(version);
    String safeApexClass = validateText(apexClass, 'Apex class name');
    String safeDeveloperName = normalizeDeveloperName(
      developerName,
      safeRoute,
      safeVersion
    );
    String safeLabel = String.isBlank(label)
      ? safeDeveloperName.replace('_', ' ')
      : label.trim();

    Metadata.CustomMetadata config = new Metadata.CustomMetadata();
    config.fullName = 'Rest_Config__mdt.' + safeDeveloperName;
    config.label = safeLabel.left(40);
    addValue(config, 'Active__c', active == null ? true : active);
    addValue(config, 'Default__c', defaultVersion == true);
    addValue(config, 'Route__c', safeRoute);
    addValue(config, 'Version__c', safeVersion);
    addValue(config, 'Apex__c', safeApexClass);

    String jobId = deployments.enqueue(config);
    return new EndpointCreationResult(
      jobId,
      config.fullName,
      safeRoute,
      safeVersion,
      safeApexClass
    );
  }

  static void addValue(
    Metadata.CustomMetadata config,
    String field,
    Object value
  ) {
    Metadata.CustomMetadataValue fieldValue = new Metadata.CustomMetadataValue();
    fieldValue.field = field;
    fieldValue.value = value;
    config.values.add(fieldValue);
  }

  static void validateStatusCode(Decimal value, String label) {
    if (value != null && (value < 100 || value > 599)) {
      throw new AuraHandledException(
        label + ' must be blank or between 100 and 599.'
      );
    }
  }

  static Decimal validateVersion(Decimal value) {
    if (value == null || value < 1 || value.scale() > 0) {
      throw new AuraHandledException(
        'Version must be a whole number greater than zero.'
      );
    }
    return value;
  }

  static String validateText(String value, String label) {
    if (String.isBlank(value)) {
      throw new AuraHandledException(label + ' is required.');
    }
    return value.trim();
  }

  static String normalizeRoute(String value) {
    String route = validateText(value, 'Route');
    while (route.startsWith('/'))
      route = route.substring(1);
    while (route.endsWith('/'))
      route = route.left(route.length() - 1);
    if (String.isBlank(route) || route.contains('/')) {
      throw new AuraHandledException(
        'Route must be one root segment without slashes.'
      );
    }
    return route.toLowerCase();
  }

  static String normalizeDeveloperName(
    String developerName,
    String route,
    Decimal version
  ) {
    String value = String.isBlank(developerName)
      ? route + '_v' + String.valueOf(version.intValue())
      : developerName.trim();
    value = value.replaceAll('[^A-Za-z0-9_]', '_').replaceAll('_+', '_');
    while (value.startsWith('_'))
      value = value.substring(1);
    while (value.endsWith('_'))
      value = value.left(value.length() - 1);
    if (String.isBlank(value))
      value = 'Rest_Config';
    Integer firstChar = value.left(1).charAt(0);
    if (firstChar < 65 || (firstChar > 90 && firstChar < 97) || firstChar > 122)
      value = 'Rest_' + value;
    return value.left(40);
  }

  static void saveSettingsRecord(Rest_Settings__c settings, Boolean isNew) {
    if (isNew) {
      assertCanCreateSettings();
      DML.insertRecords(new List<SObject>{ settings });
      return;
    }

    assertCanUpdateSettings();
    DML.updateRecords(new List<SObject>{ settings });
  }

  static void assertCanCreateSettings() {
    if (
      !Schema.sObjectType.Rest_Settings__c.isCreateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Unknown_Route_Status_Code__c.isCreateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Inactive_Route_Status_Code__c.isCreateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Unsupported_Method_Status_Code__c.isCreateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Access_Denied_Status_Code__c.isCreateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Expose_Error_Details__c.isCreateable()
    ) {
      throw new AuraHandledException(
        'You do not have permission to create REST settings.'
      );
    }
  }

  static void assertCanUpdateSettings() {
    if (
      !Schema.sObjectType.Rest_Settings__c.isUpdateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Unknown_Route_Status_Code__c.isUpdateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Inactive_Route_Status_Code__c.isUpdateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Unsupported_Method_Status_Code__c.isUpdateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Access_Denied_Status_Code__c.isUpdateable() ||
      !Schema.sObjectType.Rest_Settings__c.fields.Expose_Error_Details__c.isUpdateable()
    ) {
      throw new AuraHandledException(
        'You do not have permission to update REST settings.'
      );
    }
  }

  static List<RestClassOption> restClassOptions(List<ApexClass> classes) {
    List<RestClassOption> options = new List<RestClassOption>();
    for (ApexClass apexClass : classes) {
      options.add(new RestClassOption(apexClass));
    }
    return options;
  }

  public class ConsoleState {
    @AuraEnabled
    public Datetime generatedAt;
    @AuraEnabled
    public Integer refreshIntervalSeconds;
    @AuraEnabled
    public Integer routeCount = 0;
    @AuraEnabled
    public Integer activeRouteCount = 0;
    @AuraEnabled
    public Integer inactiveRouteCount = 0;
    @AuraEnabled
    public Integer versionedRouteCount = 0;
    Set<Decimal> versionCount = new Set<Decimal>();
    @AuraEnabled
    public SettingsRow settings;
    @AuraEnabled
    public List<RouteRow> routes = new List<RouteRow>();
    @AuraEnabled
    public List<RestClassOption> restClasses = new List<RestClassOption>();
  }

  public virtual with sharing class QueryService {
    public virtual List<Rest_Config__mdt> getConfigs() {
      return (List<Rest_Config__mdt>) Query.records(
        [
          SELECT
            Id,
            DeveloperName,
            MasterLabel,
            Active__c,
            Default__c,
            Route__c,
            Version__c,
            Apex__c
          FROM Rest_Config__mdt
          ORDER BY Route__c ASC, Version__c DESC, DeveloperName ASC
        ]
      );
    }

    public virtual Rest_Settings__c getOrganizationSettings() {
      List<Rest_Settings__c> settings = (List<Rest_Settings__c>) Query.records(
        [
          SELECT
            Id,
            SetupOwnerId,
            Unknown_Route_Status_Code__c,
            Inactive_Route_Status_Code__c,
            Unsupported_Method_Status_Code__c,
            Access_Denied_Status_Code__c,
            Expose_Error_Details__c
          FROM Rest_Settings__c
          WHERE SetupOwnerId = :UserInfo.getOrganizationId()
          LIMIT 1
        ]
      );
      return settings.isEmpty() ? null : settings[0];
    }

    public virtual List<ApexClass> getRestClasses() {
      List<ApexClass> classes;
      try {
        classes = (List<ApexClass>) Query.records(
          [
            SELECT Name, Body
            FROM ApexClass
            WHERE Status = 'Active'
            ORDER BY Name ASC
          ]
        );
      } catch (Exception e) {
        return new List<ApexClass>();
      }

      List<ApexClass> restClasses = new List<ApexClass>();

      for (ApexClass candidate : classes) {
        if (isRestClass(candidate.Body)) {
          restClasses.add(candidate);
        }
      }

      return restClasses;
    }
  }

  public virtual with sharing class DeployService {
    public virtual String enqueue(Metadata.CustomMetadata config) {
      Metadata.DeployContainer container = new Metadata.DeployContainer();
      container.addMetadata(config);
      return String.valueOf(
        Metadata.Operations.enqueueDeployment(container, null)
      );
    }
  }

  public class SettingsRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Boolean hasRecord;
    @AuraEnabled
    public Decimal unknownRouteStatusCode;
    @AuraEnabled
    public Decimal inactiveRouteStatusCode;
    @AuraEnabled
    public Decimal unsupportedMethodStatusCode;
    @AuraEnabled
    public Decimal accessDeniedStatusCode;
    @AuraEnabled
    public Boolean exposeErrorDetails;
    @AuraEnabled
    public Integer effectiveUnknownRouteStatusCode;
    @AuraEnabled
    public Integer effectiveInactiveRouteStatusCode;
    @AuraEnabled
    public Integer effectiveUnsupportedMethodStatusCode;
    @AuraEnabled
    public Integer effectiveAccessDeniedStatusCode;

    SettingsRow(Rest_Settings__c settings) {
      this.id = settings == null ? null : settings.Id;
      this.hasRecord = settings != null;
      this.unknownRouteStatusCode = settings == null
        ? null
        : settings.Unknown_Route_Status_Code__c;
      this.inactiveRouteStatusCode = settings == null
        ? null
        : settings.Inactive_Route_Status_Code__c;
      this.unsupportedMethodStatusCode = settings == null
        ? null
        : settings.Unsupported_Method_Status_Code__c;
      this.accessDeniedStatusCode = settings == null
        ? null
        : settings.Access_Denied_Status_Code__c;
      this.exposeErrorDetails =
        settings != null &&
        settings.Expose_Error_Details__c == true;
      this.effectiveUnknownRouteStatusCode = statusCode(
        this.unknownRouteStatusCode,
        404
      );
      this.effectiveInactiveRouteStatusCode = statusCode(
        this.inactiveRouteStatusCode,
        404
      );
      this.effectiveUnsupportedMethodStatusCode = statusCode(
        this.unsupportedMethodStatusCode,
        405
      );
      this.effectiveAccessDeniedStatusCode = statusCode(
        this.accessDeniedStatusCode,
        403
      );
    }

    Integer statusCode(Decimal value, Integer fallback) {
      return value == null ||
        value < 100 ||
        value > 599
        ? fallback
        : value.intValue();
    }
  }

  public class RouteRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String developerName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public String route;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public String apexClass;
    @AuraEnabled
    public Boolean isDefaultVersion;
    @AuraEnabled
    public String versionLabel;
    @AuraEnabled
    public String defaultLabel;
    @AuraEnabled
    public String endpointUrl;
    @AuraEnabled
    public String unversionedUrl;

    RouteRow(Rest_Config__mdt config) {
      this.id = config.Id;
      this.developerName = config.DeveloperName;
      this.label = config.MasterLabel;
      this.isActive = config.Active__c == true;
      this.route = config.Route__c;
      this.version = config.Version__c;
      this.apexClass = config.Apex__c;
      this.isDefaultVersion = config.Default__c == true;
      this.versionLabel = config.Version__c == null
        ? 'Unversioned'
        : 'v' + String.valueOf(config.Version__c.intValue());
      this.defaultLabel = this.isDefaultVersion
        ? 'Default'
        : 'Fallback candidate';
      this.endpointUrl = config.Version__c == null
        ? '/services/apexrest/api/' + config.Route__c
        : '/services/apexrest/api/v' +
          String.valueOf(config.Version__c.intValue()) +
          '/' +
          config.Route__c;
      this.unversionedUrl = '/services/apexrest/api/' + config.Route__c;
    }
  }

  public class RestClassOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    RestClassOption(ApexClass apexClass) {
      this.label = apexClass.Name;
      this.value = apexClass.Name;
    }
  }

  public class EndpointCreationResult {
    @AuraEnabled
    public String deploymentJobId;
    @AuraEnabled
    public String fullName;
    @AuraEnabled
    public String route;
    @AuraEnabled
    public Decimal version;
    @AuraEnabled
    public String apexClass;
    @AuraEnabled
    public String endpointUrl;

    EndpointCreationResult(
      String deploymentJobId,
      String fullName,
      String route,
      Decimal version,
      String apexClass
    ) {
      this.deploymentJobId = deploymentJobId;
      this.fullName = fullName;
      this.route = route;
      this.version = version;
      this.apexClass = apexClass;
      this.endpointUrl =
        '/services/apexrest/api/v' +
        String.valueOf(version.intValue()) +
        '/' +
        route;
    }
  }

  @testVisible
  static Boolean isRestClass(String body) {
    if (String.isBlank(body))
      return false;
    String normalizedBody = body.replaceAll('\\s+', ' ').toLowerCase();
    return normalizedBody.contains(' extends rest ') ||
      normalizedBody.contains(' extends rest{');
  }
}
