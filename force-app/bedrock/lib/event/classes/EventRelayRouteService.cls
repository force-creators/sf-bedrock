/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class EventRelayRouteService {
    public virtual List<EventRelay.Route> forSObject(String payloadType) {
        return forSObject(payloadType, null);
    }

    public virtual List<EventRelay.Route> forSObject(
        String payloadType,
        String direction
    ) {
        List<EventRelay.Route> resolvedRoutes = new List<EventRelay.Route>();
        for (Event_Config__mdt config : EventRelay.metadata.getConfigs()) {
            if (
                !matches(
                    config,
                    EventRelay.consts.PLATFORM_EVENT,
                    EventRelay.consts.ROUTING_KEY_SOBJECT_TYPE,
                    payloadType,
                    direction
                )
            )
                continue;
            resolvedRoutes.add(toRoute(config, payloadType, direction));
        }
        return resolvedRoutes;
    }

    public virtual List<EventRelay.Route> forGeneric(Generic payload) {
        return forGeneric(payload, null);
    }

    public virtual List<EventRelay.Route> forGeneric(
        Generic payload,
        String direction
    ) {
        List<EventRelay.Route> resolvedRoutes = new List<EventRelay.Route>();
        if (payload == null)
            return resolvedRoutes;

        for (Event_Config__mdt config : EventRelay.metadata.getConfigs()) {
            if (
                !matchesSourceAndDirection(
                    config,
                    EventRelay.consts.GENERIC_PAYLOAD,
                    direction
                ) || String.isBlank(config.Routing_Key__c)
            ) {
                continue;
            }

            String routingValue = (String) payload.get(
                config.Routing_Key__c,
                String.class
            );
            if (routingValue == config.Routing_Value__c) {
                resolvedRoutes.add(
                    toRoute(
                        config,
                        EventRelay.consts.GENERIC_PAYLOAD,
                        direction
                    )
                );
            }
        }
        return resolvedRoutes;
    }

    public virtual String idempotencyKeyPathForSObject(
        String payloadType,
        String direction,
        String apexClass
    ) {
        for (Event_Config__mdt config : EventRelay.metadata.getConfigs()) {
            if (
                !matches(
                    config,
                    EventRelay.consts.PLATFORM_EVENT,
                    EventRelay.consts.ROUTING_KEY_SOBJECT_TYPE,
                    payloadType,
                    direction
                )
            )
                continue;
            if (
                matchesApex(
                    config,
                    EventRelay.consts.PLATFORM_EVENT,
                    direction,
                    apexClass
                )
            )
                return config.Idempotency_Key_Path__c;
        }
        return null;
    }

    public virtual String idempotencyKeyPathForGeneric(
        Generic payload,
        String direction,
        String apexClass
    ) {
        if (payload == null)
            return null;

        for (Event_Config__mdt config : EventRelay.metadata.getConfigs()) {
            if (
                !matchesSourceAndDirection(
                    config,
                    EventRelay.consts.GENERIC_PAYLOAD,
                    direction
                ) ||
                String.isBlank(config.Routing_Key__c) ||
                !matchesApex(
                    config,
                    EventRelay.consts.GENERIC_PAYLOAD,
                    direction,
                    apexClass
                )
            ) {
                continue;
            }

            String routingValue = (String) payload.get(
                config.Routing_Key__c,
                String.class
            );
            if (routingValue == config.Routing_Value__c)
                return config.Idempotency_Key_Path__c;
        }
        return null;
    }

    Boolean matches(
        Event_Config__mdt config,
        String sourceType,
        String routingKey,
        String routingValue,
        String direction
    ) {
        return matchesSourceAndDirection(config, sourceType, direction) &&
            config.Routing_Key__c == routingKey &&
            config.Routing_Value__c == routingValue;
    }

    Boolean matchesSourceAndDirection(
        Event_Config__mdt config,
        String sourceType,
        String direction
    ) {
        if (config == null || config.Active__c != true)
            return false;
        if (config.Source_Type__c != sourceType)
            return false;
        if (String.isBlank(direction))
            return true;
        return config.Direction__c == direction ||
            config.Direction__c == EventRelay.consts.BOTH;
    }

    Boolean matchesApex(
        Event_Config__mdt config,
        String sourceType,
        String direction,
        String apexClass
    ) {
        String configuredApex = config.Apex__c;
        if (
            sourceType == EventRelay.consts.PLATFORM_EVENT &&
            direction == EventRelay.consts.PUBLISH &&
            String.isBlank(configuredApex)
        ) {
            configuredApex = EventRelay.consts.PLATFORM_EVENT_PUBLISHER;
        }
        return configuredApex == apexClass;
    }

    EventRelay.Route toRoute(
        Event_Config__mdt config,
        String payloadType,
        String direction
    ) {
        String apexClass = config.Apex__c;
        if (
            direction == EventRelay.consts.PUBLISH &&
            payloadType != EventRelay.consts.GENERIC_PAYLOAD &&
            String.isBlank(apexClass)
        ) {
            apexClass = EventRelay.consts.PLATFORM_EVENT_PUBLISHER;
        }
        if (String.isBlank(apexClass)) {
            throw new EventRelay.EventRelayException(
                'Event_Config__mdt ' +
                    config.DeveloperName +
                    ' requires Apex__c.'
            );
        }
        return new EventRelay.Route(
            config.DeveloperName,
            apexClass,
            payloadType,
            config.DeveloperName,
            config.Idempotency_Key_Path__c
        );
    }
}
