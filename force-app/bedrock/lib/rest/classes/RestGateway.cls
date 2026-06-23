/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@RestResource(urlMapping='/api/*')
global inherited sharing class RestGateway {
    @HttpGet
    global static void doGet() {
        Rest.dispatch('GET');
    }

    @HttpPost
    global static void doPost() {
        Rest.dispatch('POST');
    }

    @HttpPut
    global static void doPut() {
        Rest.dispatch('PUT');
    }

    @HttpPatch
    global static void doPatch() {
        Rest.dispatch('PATCH');
    }

    @HttpDelete
    global static void doDelete() {
        Rest.dispatch('DELETE');
    }
}
