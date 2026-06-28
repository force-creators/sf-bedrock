/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public inherited sharing class RestCatalogEndpoint extends Rest {
    public override void get(Rest.Request request) {
        List<Object> routes = new List<Object>();
        for (Rest_Config__mdt config : Rest.metadata.getConfigs()) {
            routes.add(
                new Map<String, Object>{
                    'developerName' => config.DeveloperName,
                    'label' => config.MasterLabel,
                    'active' => config.Active__c,
                    'defaultVersion' => config.Default__c,
                    'route' => config.Route__c,
                    'version' => config.Version__c,
                    'apexClass' => config.Apex__c,
                    'endpointUrl' => endpointUrl(config)
                }
            );
        }

        respond(
            new Map<String, Object>{
                'count' => routes.size(),
                'routes' => routes
            }
        );
    }

    String endpointUrl(Rest_Config__mdt config) {
        if (config.Version__c == null)
            return '/services/apexrest/api/' + config.Route__c;
        return '/services/apexrest/api/v' +
            String.valueOf(config.Version__c.intValue()) +
            '/' +
            config.Route__c;
    }
}
