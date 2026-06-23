/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest
public inherited sharing class RestTestAccountRest extends Rest {
    public override void get(Rest.Request request) {
        respond(
            new Map<String, Object>{
                'endpoint' => 'accounts',
                'version' => request.version,
                'primaryContext' => request.primaryContext,
                'primaryId' => request.primaryId,
                'ids' => request.ids,
                'include' => request.params.get('include'),
                'name' => request.body.get('name')
            }
        );
    }

    public override void post(Rest.Request request) {
        respond(
            201,
            new Map<String, Object>{
                'endpoint' => 'accounts',
                'name' => request.body.get('name')
            }
        );
    }

    public override Boolean canAccess(Rest.Request request) {
        return request.params.get('deny') != 'true';
    }

    public class Contacts extends Rest {
        public override void get(Rest.Request request) {
            respond(
                new Map<String, Object>{
                    'endpoint' => 'contacts',
                    'primaryContext' => request.primaryContext,
                    'secondaryContext' => request.secondaryContext,
                    'primaryId' => request.primaryId,
                    'secondaryId' => request.secondaryId
                }
            );
        }
    }
}
