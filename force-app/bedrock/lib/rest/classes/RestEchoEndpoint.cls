/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public inherited sharing class RestEchoEndpoint extends Rest {
    public override void get(Rest.Request request) {
        respond(payload(request));
    }

    public override void post(Rest.Request request) {
        respond(201, payload(request));
    }

    Map<String, Object> payload(Rest.Request request) {
        return new Map<String, Object>{
            'route' => request.route,
            'version' => request.version,
            'primaryContext' => request.primaryContext,
            'secondaryContext' => request.secondaryContext,
            'primaryId' => request.primaryId,
            'secondaryId' => request.secondaryId,
            'ids' => request.ids,
            'params' => request.params,
            'body' => request.body
        };
    }
}
