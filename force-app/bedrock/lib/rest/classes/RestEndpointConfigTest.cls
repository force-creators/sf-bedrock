@istest(testFor='ApexClass:Rest')
private class RestEndpointConfigTest {
    @istest static void testHealthEndpoint_returnsOk() {
        seedRoutes();
        request('GET', '/services/apexrest/api/v1/health', null, null);

        RestGateway.doGet();

        Map<String, Object> body = responseBody();
        Assert.areEqual(200, RestContext.response.statusCode, 'Expected health endpoint to return a successful response.');
        Assert.areEqual('ok', body.get('status'), 'Expected health endpoint to report ok status.');
        Assert.areEqual('health', body.get('route'), 'Expected health endpoint to receive the configured route.');
        Assert.areEqual('v1', body.get('version'), 'Expected health endpoint to receive the configured version.');
    }

    @istest static void testEchoEndpoint_returnsRequestShape() {
        seedRoutes();
        request(
            'POST',
            '/services/apexrest/api/v1/echo/001000000000001AAA',
            new Map<String, String> { 'ids' => '001000000000001AAA' },
            '{"message":"hello"}'
        );

        RestGateway.doPost();

        Map<String, Object> body = responseBody();
        Assert.areEqual(201, RestContext.response.statusCode, 'Expected echo POST to return a created-style response.');
        Assert.areEqual('echo', body.get('route'), 'Expected echo endpoint to receive the configured route.');
        Assert.areEqual('001000000000001AAA', body.get('primaryContext'), 'Expected echo endpoint to expose primary context.');
        Assert.areEqual(1, ((List<Object>) body.get('ids')).size(), 'Expected echo endpoint to return parsed ids.');
        Assert.areEqual('hello', ((Map<String, Object>) body.get('body')).get('message'), 'Expected echo endpoint to return parsed body values.');
    }

    @istest static void testCatalogEndpoint_returnsConfiguredRoutes() {
        seedRoutes();
        Query.setMock(new QueryMock(new List<SObject> {
            config('health-v1', true, 'health', 1, 'RestHealthEndpoint'),
            config('echo-v1', true, 'echo', 1, 'RestEchoEndpoint'),
            config('catalog-v1', true, 'catalog', 1, 'RestCatalogEndpoint')
        }));
        request('GET', '/services/apexrest/api/v1/catalog', null, null);

        RestGateway.doGet();

        Map<String, Object> body = responseBody();
        Assert.areEqual(200, RestContext.response.statusCode, 'Expected catalog endpoint to return a successful response.');
        Assert.areEqual(3, Integer.valueOf(String.valueOf(body.get('count'))), 'Expected catalog endpoint to report configured routes.');
        Assert.areEqual(3, ((List<Object>) body.get('routes')).size(), 'Expected catalog endpoint to return route rows.');
    }

    static void seedRoutes() {
        Rest.reset();
        Rest.setMock(new RestMock().seedConfigs(new List<Rest_Config__mdt> {
            config('health-v1', true, 'health', 1, 'RestHealthEndpoint'),
            config('echo-v1', true, 'echo', 1, 'RestEchoEndpoint'),
            config('catalog-v1', true, 'catalog', 1, 'RestCatalogEndpoint')
        }));
    }

    static Rest_Config__mdt config(String developerName, Boolean active, String route, Integer version, String apexClass) {
        Rest_Config__mdt config = new Rest_Config__mdt();
        config.DeveloperName = developerName;
        config.MasterLabel = developerName.replace('-', ' ');
        config.Active__c = active;
        config.Route__c = route;
        config.Version__c = version;
        config.Apex__c = apexClass;
        return config;
    }

    static void request(String method, String uri, Map<String, String> params, String body) {
        RestRequest request = new RestRequest();
        request.httpMethod = method;
        request.requestURI = uri;
        if (params != null) {
            for (String key : params.keySet()) {
                request.addParameter(key, params.get(key));
            }
        }
        if (body != null) request.requestBody = Blob.valueOf(body);
        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    static Map<String, Object> responseBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }
}
