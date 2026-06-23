/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:Rest')
private class RestTest {
    static final String ACCOUNT_ID = '001000000000001AAA';
    static final String CONTACT_ID = '003000000000001AAA';

    @istest
    static void testGet_resolvesVersionedRootRoute() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request('GET', '/services/apexrest/api/v1/accounts', null, null);

        RestGateway.doGet();

        Assert.areEqual(
            200,
            RestContext.response.statusCode,
            'Expected versioned route to return a successful response.'
        );
        Map<String, Object> body = responseBody();
        Assert.areEqual(
            'accounts',
            body.get('endpoint'),
            'Expected root account endpoint to handle the request.'
        );
        Assert.areEqual(
            'v1',
            body.get('version'),
            'Expected request version to be exposed to the endpoint.'
        );
    }

    @istest
    static void testGet_usesConfiguredDefaultVersionWhenVersionOmitted() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                ),
                config(
                    'accounts-v2',
                    true,
                    false,
                    'accounts',
                    2,
                    'RestTestAccountRest'
                )
            }
        );
        request('GET', '/services/apexrest/api/accounts', null, null);

        RestGateway.doGet();

        Assert.areEqual(
            200,
            RestContext.response.statusCode,
            'Expected route without URL version to resolve.'
        );
        Assert.areEqual(
            'v1',
            responseBody().get('version'),
            'Expected configured default version to be selected before latest active version.'
        );
    }

    @istest
    static void testGet_usesLatestActiveVersionWhenVersionOmittedAndNoDefaultConfigured() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                ),
                config(
                    'accounts-v2',
                    true,
                    'accounts',
                    2,
                    'RestTestAccountRest'
                )
            }
        );
        request('GET', '/services/apexrest/api/accounts', null, null);

        RestGateway.doGet();

        Assert.areEqual(
            200,
            RestContext.response.statusCode,
            'Expected route without URL version to resolve.'
        );
        Assert.areEqual(
            'v2',
            responseBody().get('version'),
            'Expected latest active version to be selected when no URL version is provided.'
        );
    }

    @istest
    static void testGet_returnsErrorForDuplicateDefaultRouteVersions() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                ),
                config(
                    'accounts-v2',
                    true,
                    true,
                    'accounts',
                    2,
                    'RestTestAccountRest'
                )
            }
        );
        request('GET', '/services/apexrest/api/accounts', null, null);

        RestGateway.doGet();

        Assert.areEqual(
            500,
            RestContext.response.statusCode,
            'Expected duplicate active default versions to fail deterministically.'
        );
        Assert.areEqual(
            'REST route configuration is ambiguous.',
            responseBody().get('error'),
            'Expected duplicate default error to explain the configuration problem.'
        );
    }

    @istest
    static void testGet_returnsConfiguredStatusForUnknownRoute() {
        seedRoutes(new List<Rest_Config__mdt>());
        Rest.settings.setSettings(
            new Rest_Settings__c(Unknown_Route_Status_Code__c = 410)
        );
        request('GET', '/services/apexrest/api/missing', null, null);

        RestGateway.doGet();

        Assert.areEqual(
            410,
            RestContext.response.statusCode,
            'Expected unknown routes to use the configured status code.'
        );
    }

    @istest
    static void testGet_returnsConfiguredStatusForInactiveRoute() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    false,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        Rest.settings.setSettings(
            new Rest_Settings__c(Inactive_Route_Status_Code__c = 451)
        );
        request('GET', '/services/apexrest/api/v1/accounts', null, null);

        RestGateway.doGet();

        Assert.areEqual(
            451,
            RestContext.response.statusCode,
            'Expected inactive routes to use the configured status code.'
        );
    }

    @istest
    static void testGet_returnsErrorForDuplicateActiveRouteVersion() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1-a',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                ),
                config(
                    'accounts-v1-b',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request('GET', '/services/apexrest/api/v1/accounts', null, null);

        RestGateway.doGet();

        Assert.areEqual(
            500,
            RestContext.response.statusCode,
            'Expected duplicate active route versions to fail deterministically.'
        );
        Assert.areEqual(
            'REST route configuration is ambiguous.',
            responseBody().get('error'),
            'Expected duplicate route error to explain the configuration problem.'
        );
    }

    @istest
    static void testPost_parsesBodyAndUsesMethodHandler() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request(
            'POST',
            '/services/apexrest/api/v1/accounts',
            null,
            '{"name":"Acme"}'
        );

        RestGateway.doPost();

        Assert.areEqual(
            201,
            RestContext.response.statusCode,
            'Expected POST override to control the response status.'
        );
        Assert.areEqual(
            'Acme',
            responseBody().get('name'),
            'Expected JSON request body values to be available on request.body.'
        );
    }

    @istest
    static void testPut_returnsConfiguredUnsupportedMethodStatus() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        Rest.settings.setSettings(
            new Rest_Settings__c(Unsupported_Method_Status_Code__c = 409)
        );
        request('PUT', '/services/apexrest/api/v1/accounts', null, null);

        RestGateway.doPut();

        Assert.areEqual(
            409,
            RestContext.response.statusCode,
            'Expected unsupported methods to use the configured status code.'
        );
    }

    @istest
    static void testGet_returnsConfiguredAccessDeniedStatus() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        Rest.settings.setSettings(
            new Rest_Settings__c(Access_Denied_Status_Code__c = 401)
        );
        request(
            'GET',
            '/services/apexrest/api/v1/accounts',
            new Map<String, String>{ 'deny' => 'true' },
            null
        );

        RestGateway.doGet();

        Assert.areEqual(
            401,
            RestContext.response.statusCode,
            'Expected canAccess failures to use the configured status code.'
        );
    }

    @istest
    static void testGet_populatesContextParamsBodyAndQueryIds() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request(
            'GET',
            '/services/apexrest/api/v1/accounts/' + ACCOUNT_ID,
            new Map<String, String>{
                'include' => 'inactive',
                'ids' => ACCOUNT_ID +
                ',' +
                CONTACT_ID
            },
            '{"name":"Ignored"}'
        );

        RestGateway.doGet();

        Map<String, Object> body = responseBody();
        Assert.areEqual(
            ACCOUNT_ID,
            body.get('primaryContext'),
            'Expected one non-sub-endpoint segment to become primary context.'
        );
        Assert.areEqual(
            ACCOUNT_ID,
            body.get('primaryId'),
            'Expected Id-shaped primary context to populate primaryId.'
        );
        Assert.areEqual(
            'inactive',
            body.get('include'),
            'Expected query params to be available on request.params.'
        );
        Assert.areEqual(
            2,
            ((List<Object>) body.get('ids')).size(),
            'Expected comma-separated query ids to populate request.ids.'
        );
    }

    @istest
    static void testGet_populatesBodyIdsWhenQueryIdsMissing() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request(
            'GET',
            '/services/apexrest/api/v1/accounts',
            null,
            '{"ids":["' + ACCOUNT_ID + '","' + CONTACT_ID + '"]}'
        );

        RestGateway.doGet();

        Assert.areEqual(
            2,
            ((List<Object>) responseBody().get('ids')).size(),
            'Expected body ids to populate request.ids when query ids are absent.'
        );
    }

    @istest
    static void testGet_resolvesSingleSegmentSubEndpointBeforeContext() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request(
            'GET',
            '/services/apexrest/api/v1/accounts/contacts',
            null,
            null
        );

        RestGateway.doGet();

        Map<String, Object> body = responseBody();
        Assert.areEqual(
            'contacts',
            body.get('endpoint'),
            'Expected sub-endpoint to win over context for one remaining segment.'
        );
        Assert.areEqual(
            null,
            body.get('primaryContext'),
            'Expected no primary context when the segment resolves as a sub-endpoint.'
        );
    }

    @istest
    static void testGet_resolvesPrimaryContextThenSubEndpoint() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request(
            'GET',
            '/services/apexrest/api/v1/accounts/' + ACCOUNT_ID + '/contacts',
            null,
            null
        );

        RestGateway.doGet();

        Map<String, Object> body = responseBody();
        Assert.areEqual(
            'contacts',
            body.get('endpoint'),
            'Expected second segment to resolve as a sub-endpoint.'
        );
        Assert.areEqual(
            ACCOUNT_ID,
            body.get('primaryContext'),
            'Expected first segment to become primary context.'
        );
        Assert.areEqual(
            ACCOUNT_ID,
            body.get('primaryId'),
            'Expected Id-shaped primary context to populate primaryId.'
        );
    }

    @istest
    static void testGet_resolvesSubEndpointThenPrimaryContext() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request(
            'GET',
            '/services/apexrest/api/v1/accounts/contacts/' + CONTACT_ID,
            null,
            null
        );

        RestGateway.doGet();

        Map<String, Object> body = responseBody();
        Assert.areEqual(
            'contacts',
            body.get('endpoint'),
            'Expected first segment to resolve as a sub-endpoint.'
        );
        Assert.areEqual(
            CONTACT_ID,
            body.get('primaryContext'),
            'Expected second segment to become primary context on the sub-endpoint.'
        );
        Assert.areEqual(
            CONTACT_ID,
            body.get('primaryId'),
            'Expected Id-shaped sub-endpoint context to populate primaryId.'
        );
    }

    @istest
    static void testGet_resolvesPrimarySubEndpointAndSecondaryContext() {
        seedRoutes(
            new List<Rest_Config__mdt>{
                config(
                    'accounts-v1',
                    true,
                    'accounts',
                    1,
                    'RestTestAccountRest'
                )
            }
        );
        request(
            'GET',
            '/services/apexrest/api/v1/accounts/' +
                ACCOUNT_ID +
                '/contacts/' +
                CONTACT_ID,
            null,
            null
        );

        RestGateway.doGet();

        Map<String, Object> body = responseBody();
        Assert.areEqual(
            'contacts',
            body.get('endpoint'),
            'Expected middle segment to resolve as a sub-endpoint.'
        );
        Assert.areEqual(
            ACCOUNT_ID,
            body.get('primaryContext'),
            'Expected first segment to become primary context.'
        );
        Assert.areEqual(
            CONTACT_ID,
            body.get('secondaryContext'),
            'Expected third segment to become secondary context.'
        );
        Assert.areEqual(
            CONTACT_ID,
            body.get('secondaryId'),
            'Expected Id-shaped secondary context to populate secondaryId.'
        );
    }

    static void seedRoutes(List<Rest_Config__mdt> configs) {
        Rest.reset();
        Rest.setMock(new RestMock().seedConfigs(configs));
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
        config.Active__c = active;
        config.Default__c = defaultVersion;
        config.Route__c = route;
        config.Version__c = version;
        config.Apex__c = apexClass;
        return config;
    }

    static void request(
        String method,
        String uri,
        Map<String, String> params,
        String body
    ) {
        RestRequest request = new RestRequest();
        request.httpMethod = method;
        request.requestURI = uri;
        if (params != null) {
            for (String key : params.keySet()) {
                request.addParameter(key, params.get(key));
            }
        }
        if (body != null)
            request.requestBody = Blob.valueOf(body);
        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    static Map<String, Object> responseBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }
}
