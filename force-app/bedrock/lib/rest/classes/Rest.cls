/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual inherited sharing class Rest {
    public static MetadataService metadata = new MetadataService();
    public static SettingsService settings = new SettingsService();
    public static Service service = new Service();

    @testVisible
    String apexClassName;
    @testVisible
    Request currentRequest;

    @testVisible
    static void setMock(RestMock mock) {
        metadata = mock.metadata;
        settings = mock.settings;
        service = mock.service;
    }

    @testVisible
    static void reset() {
        metadata = new MetadataService();
        settings = new SettingsService();
        service = new Service();
    }

    public static void dispatch(String method) {
        service.dispatch(method);
    }

    public virtual void get(Request request) {
        methodNotAllowed();
    }

    public virtual void post(Request request) {
        methodNotAllowed();
    }

    public virtual void put(Request request) {
        methodNotAllowed();
    }

    public virtual void patch(Request request) {
        methodNotAllowed();
    }

    public virtual void del(Request request) {
        methodNotAllowed();
    }

    public virtual Boolean canAccess(Request request) {
        return true;
    }

    protected void respond(Object body) {
        respond(200, body);
    }

    protected void respond(Integer statusCode, Object body) {
        RestResponse response = response();
        response.statusCode = safeStatusCode(statusCode, 200);
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    protected void error(Integer statusCode, String message) {
        writeError(safeStatusCode(statusCode, 500), message);
    }

    void methodNotAllowed() {
        writeError(
            settings.unsupportedMethodStatusCode(),
            'HTTP method is not supported for this endpoint.'
        );
    }

    static void writeError(Integer statusCode, String message) {
        RestResponse response = response();
        response.statusCode = safeStatusCode(statusCode, 500);
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(
            JSON.serialize(
                new Map<String, Object>{
                    'error' => String.isBlank(message)
                        ? 'REST request failed.'
                        : message
                }
            )
        );
    }

    static RestResponse response() {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        return RestContext.response;
    }

    static Integer safeStatusCode(Integer value, Integer fallback) {
        return value == null || value < 100 || value > 599 ? fallback : value;
    }

    public class Request {
        public RestRequest rawRequest;
        public RestResponse rawResponse;
        public String version;
        public String route;
        public List<String> segments = new List<String>();
        public String primaryContext;
        public String secondaryContext;
        public Id primaryId;
        public Id secondaryId;
        public Set<Id> ids = new Set<Id>();
        public Map<String, Object> body = new Map<String, Object>();
        public Map<String, String> params = new Map<String, String>();

        Integer versionNumber() {
            if (String.isBlank(version))
                return null;
            return Integer.valueOf(version.substring(1));
        }
    }

    public virtual inherited sharing class Service {
        public virtual void dispatch(String method) {
            try {
                Request request = buildRequest();
                RouteMatch match = metadata.resolve(
                    request.route,
                    request.versionNumber()
                );
                if (match.statusCode != null) {
                    writeError(match.statusCode, match.message);
                    return;
                }

                Rest endpoint = instantiate(match.config.Apex__c);
                request.version =
                    'v' + String.valueOf(match.config.Version__c.intValue());
                endpoint = route(endpoint, request);
                if (!endpoint.canAccess(request)) {
                    writeError(
                        settings.accessDeniedStatusCode(),
                        'Access denied.'
                    );
                    return;
                }

                invoke(endpoint, method, request);
            } catch (Exception error) {
                String message = settings.exposeErrorDetails()
                    ? error.getTypeName() + ': ' + error.getMessage()
                    : 'REST request failed.';
                writeError(500, message);
            }
        }

        public virtual Request buildRequest() {
            RestRequest rawRequest = RestContext.request == null
                ? new RestRequest()
                : RestContext.request;
            Request request = new Request();
            request.rawRequest = rawRequest;
            request.rawResponse = response();
            request.params.putAll(
                rawRequest.params == null
                    ? new Map<String, String>()
                    : rawRequest.params
            );
            request.body = parseBody(rawRequest);
            request.ids = parseIds(request);

            List<String> pathSegments = pathSegments(rawRequest.requestURI);
            if (!pathSegments.isEmpty() && isVersion(pathSegments[0])) {
                request.version = pathSegments.remove(0).toLowerCase();
            }
            if (pathSegments.isEmpty()) {
                request.route = null;
                return request;
            }

            request.route = normalize(pathSegments.remove(0));
            request.segments.addAll(pathSegments);
            return request;
        }

        public virtual Rest route(Rest endpoint, Request request) {
            Integer count = request.segments.size();
            if (count == 0) {
                endpoint.currentRequest = request;
                return endpoint;
            }
            if (count > 3) {
                throw new RestException(
                    'REST route has too many path segments.'
                );
            }

            if (count == 1) {
                Rest child = subEndpoint(endpoint, request.segments[0]);
                if (child != null) {
                    child.currentRequest = request;
                    return child;
                }
                setPrimary(request, request.segments[0]);
                endpoint.currentRequest = request;
                return endpoint;
            }

            if (count == 2) {
                Rest child = subEndpoint(endpoint, request.segments[0]);
                if (child != null) {
                    setPrimary(request, request.segments[1]);
                    child.currentRequest = request;
                    return child;
                }

                child = subEndpoint(endpoint, request.segments[1]);
                if (child != null) {
                    setPrimary(request, request.segments[0]);
                    child.currentRequest = request;
                    return child;
                }

                throw new RestException('REST sub-endpoint was not found.');
            }

            Rest child = subEndpoint(endpoint, request.segments[1]);
            if (child == null) {
                throw new RestException('REST sub-endpoint was not found.');
            }
            setPrimary(request, request.segments[0]);
            setSecondary(request, request.segments[2]);
            child.currentRequest = request;
            return child;
        }

        public virtual Rest subEndpoint(Rest endpoint, String segment) {
            String childClassName =
                endpoint.apexClassName +
                '.' +
                className(segment);
            Type childType = Type.forName(childClassName);
            if (childType == null)
                return null;
            return instantiate(childClassName);
        }

        public virtual Rest instantiate(String apexClassName) {
            if (String.isBlank(apexClassName)) {
                throw new RestException('REST handler Apex class is blank.');
            }

            Type endpointType = Type.forName(apexClassName.trim());
            if (endpointType == null) {
                throw new RestException(
                    'REST handler Apex class was not found: ' +
                        apexClassName +
                        '.'
                );
            }

            Object instance = endpointType.newInstance();
            Rest endpoint = (Rest) instance;
            endpoint.apexClassName = apexClassName.trim();
            return endpoint;
        }

        public virtual void invoke(
            Rest endpoint,
            String method,
            Request request
        ) {
            String normalizedMethod = String.isBlank(method)
                ? ''
                : method.trim().toUpperCase();
            if (normalizedMethod == 'GET') {
                endpoint.get(request);
            } else if (normalizedMethod == 'POST') {
                endpoint.post(request);
            } else if (normalizedMethod == 'PUT') {
                endpoint.put(request);
            } else if (normalizedMethod == 'PATCH') {
                endpoint.patch(request);
            } else if (normalizedMethod == 'DELETE') {
                endpoint.del(request);
            } else {
                endpoint.methodNotAllowed();
            }
        }

        List<String> pathSegments(String requestUri) {
            String uri = String.isBlank(requestUri) ? '' : requestUri;
            Integer queryStart = uri.indexOf('?');
            if (queryStart >= 0)
                uri = uri.left(queryStart);

            Integer apiStart = uri.indexOf('/api');
            String path = apiStart >= 0 ? uri.substring(apiStart + 4) : uri;
            while (path.startsWith('/'))
                path = path.substring(1);
            while (path.endsWith('/'))
                path = path.left(path.length() - 1);

            List<String> segments = new List<String>();
            if (String.isBlank(path))
                return segments;
            for (String segment : path.split('/')) {
                if (!String.isBlank(segment))
                    segments.add(segment.trim());
            }
            return segments;
        }

        Map<String, Object> parseBody(RestRequest request) {
            if (request.requestBody == null)
                return new Map<String, Object>();
            String bodyText = request.requestBody.toString();
            if (String.isBlank(bodyText))
                return new Map<String, Object>();

            Object parsed = JSON.deserializeUntyped(bodyText);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
            return new Map<String, Object>();
        }

        Set<Id> parseIds(Request request) {
            Set<Id> values = new Set<Id>();
            if (request.params.containsKey('ids')) {
                addIds(values, request.params.get('ids'));
                return values;
            }

            if (request.body.containsKey('ids')) {
                Object rawIds = request.body.get('ids');
                if (rawIds instanceof List<Object>) {
                    for (Object rawId : (List<Object>) rawIds) {
                        addId(
                            values,
                            rawId == null ? null : String.valueOf(rawId)
                        );
                    }
                } else {
                    addIds(
                        values,
                        rawIds == null ? null : String.valueOf(rawIds)
                    );
                }
            }
            return values;
        }

        void addIds(Set<Id> values, String rawIds) {
            if (String.isBlank(rawIds))
                return;
            for (String rawId : rawIds.split(',')) {
                addId(values, rawId);
            }
        }

        void addId(Set<Id> values, String rawId) {
            Id value = toId(rawId);
            if (value != null)
                values.add(value);
        }

        void setPrimary(Request request, String value) {
            request.primaryContext = value;
            request.primaryId = toId(value);
        }

        void setSecondary(Request request, String value) {
            request.secondaryContext = value;
            request.secondaryId = toId(value);
        }

        Id toId(String value) {
            if (String.isBlank(value))
                return null;
            try {
                return (Id) value.trim();
            } catch (Exception error) {
                return null;
            }
        }

        Boolean isVersion(String segment) {
            if (String.isBlank(segment))
                return false;
            String value = segment.trim().toLowerCase();
            if (!value.startsWith('v') || value.length() < 2)
                return false;
            for (Integer i = 1; i < value.length(); i++) {
                Integer code = value.substring(i, i + 1).charAt(0);
                if (code < 48 || code > 57)
                    return false;
            }
            return true;
        }

        String normalize(String value) {
            if (String.isBlank(value))
                return null;
            String normalized = value.trim().toLowerCase();
            while (normalized.startsWith('/'))
                normalized = normalized.substring(1);
            while (normalized.endsWith('/'))
                normalized = normalized.left(normalized.length() - 1);
            return normalized;
        }

        String className(String segment) {
            if (String.isBlank(segment))
                return '';
            String value = segment.trim().toLowerCase();
            String result = '';
            for (String part : value.split('[^a-zA-Z0-9]+')) {
                if (String.isBlank(part))
                    continue;
                result +=
                    part.left(1).toUpperCase() +
                    (part.length() == 1 ? '' : part.substring(1));
            }
            return result;
        }
    }

    public virtual inherited sharing class MetadataService {
        @testVisible
        List<Rest_Config__mdt> configs;

        public virtual List<Rest_Config__mdt> getConfigs() {
            if (configs == null)
                configs = loadConfigs();
            return configs;
        }

        public virtual void setConfigs(List<Rest_Config__mdt> configs) {
            this.configs = configs == null
                ? new List<Rest_Config__mdt>()
                : configs;
        }

        public virtual RouteMatch resolve(String route, Integer version) {
            if (String.isBlank(route)) {
                return new RouteMatch(
                    settings.unknownRouteStatusCode(),
                    'REST route was not found.'
                );
            }

            List<Rest_Config__mdt> activeMatches = new List<Rest_Config__mdt>();
            List<Rest_Config__mdt> inactiveMatches = new List<Rest_Config__mdt>();
            for (Rest_Config__mdt config : getConfigs()) {
                if (normalize(config.Route__c) != normalize(route))
                    continue;
                if (version != null && config.Version__c != version)
                    continue;
                if (config.Active__c == true) {
                    activeMatches.add(config);
                } else {
                    inactiveMatches.add(config);
                }
            }

            if (activeMatches.isEmpty()) {
                if (!inactiveMatches.isEmpty()) {
                    return new RouteMatch(
                        settings.inactiveRouteStatusCode(),
                        'REST route is inactive.'
                    );
                }
                return new RouteMatch(
                    settings.unknownRouteStatusCode(),
                    'REST route was not found.'
                );
            }

            Decimal selectedVersion = version;
            if (selectedVersion == null) {
                List<Rest_Config__mdt> defaultMatches = new List<Rest_Config__mdt>();
                for (Rest_Config__mdt config : activeMatches) {
                    if (config.Default__c == true) {
                        defaultMatches.add(config);
                    }
                    if (
                        selectedVersion == null ||
                        config.Version__c > selectedVersion
                    ) {
                        selectedVersion = config.Version__c;
                    }
                }
                if (defaultMatches.size() == 1) {
                    selectedVersion = defaultMatches[0].Version__c;
                } else if (defaultMatches.size() > 1) {
                    return new RouteMatch(
                        500,
                        'REST route configuration is ambiguous.'
                    );
                }
            }

            List<Rest_Config__mdt> selectedMatches = new List<Rest_Config__mdt>();
            for (Rest_Config__mdt config : activeMatches) {
                if (config.Version__c == selectedVersion)
                    selectedMatches.add(config);
            }

            if (selectedMatches.size() != 1) {
                return new RouteMatch(
                    500,
                    'REST route configuration is ambiguous.'
                );
            }
            return new RouteMatch(selectedMatches[0]);
        }

        String normalize(String value) {
            if (String.isBlank(value))
                return null;
            String normalized = value.trim().toLowerCase();
            while (normalized.startsWith('/'))
                normalized = normalized.substring(1);
            while (normalized.endsWith('/'))
                normalized = normalized.left(normalized.length() - 1);
            return normalized;
        }

        protected virtual List<Rest_Config__mdt> loadConfigs() {
            return (List<Rest_Config__mdt>) Query.records(
                [
                    SELECT
                        DeveloperName,
                        Active__c,
                        Default__c,
                        Route__c,
                        Version__c,
                        Apex__c
                    FROM Rest_Config__mdt
                ]
            );
        }
    }

    public virtual inherited sharing class SettingsService {
        @testVisible
        Rest_Settings__c values;

        public virtual Integer unknownRouteStatusCode() {
            return statusCode(getSettings().Unknown_Route_Status_Code__c, 404);
        }

        public virtual Integer inactiveRouteStatusCode() {
            return statusCode(getSettings().Inactive_Route_Status_Code__c, 404);
        }

        public virtual Integer unsupportedMethodStatusCode() {
            return statusCode(
                getSettings().Unsupported_Method_Status_Code__c,
                405
            );
        }

        public virtual Integer accessDeniedStatusCode() {
            return statusCode(getSettings().Access_Denied_Status_Code__c, 403);
        }

        public virtual Boolean exposeErrorDetails() {
            return getSettings().Expose_Error_Details__c == true;
        }

        public virtual Rest_Settings__c getSettings() {
            if (values == null)
                values = loadSettings();
            return values;
        }

        public virtual void setSettings(Rest_Settings__c values) {
            this.values = values == null ? new Rest_Settings__c() : values;
        }

        Integer statusCode(Decimal value, Integer fallback) {
            return value == null ||
                value < 100 ||
                value > 599
                ? fallback
                : value.intValue();
        }

        protected virtual Rest_Settings__c loadSettings() {
            Rest_Settings__c settings = Rest_Settings__c.getInstance();
            return settings == null ? new Rest_Settings__c() : settings;
        }
    }

    public class RouteMatch {
        public Rest_Config__mdt config;
        public Integer statusCode;
        public String message;

        RouteMatch(Rest_Config__mdt config) {
            this.config = config;
        }

        RouteMatch(Integer statusCode, String message) {
            this.statusCode = statusCode;
            this.message = message;
        }
    }

    public class RestException extends Exception {
    }
}
