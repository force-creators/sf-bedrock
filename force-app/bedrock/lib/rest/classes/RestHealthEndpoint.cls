/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public inherited sharing class RestHealthEndpoint extends Rest {
  public override void get(Rest.Request request) {
    respond(
      new Map<String, Object>{
        'status' => 'ok',
        'route' => request.route,
        'version' => request.version,
        'primaryContext' => request.primaryContext,
        'secondaryContext' => request.secondaryContext
      }
    );
  }
}
