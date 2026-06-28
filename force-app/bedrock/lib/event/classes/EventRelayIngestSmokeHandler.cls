/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class EventRelayIngestSmokeHandler extends EventRelay.Handler {
    public override void execute(List<Generic> records) {
        List<SObject> contacts = new List<SObject>();
        for (Generic record : records) {
            contacts.add(
                new Contact(
                    LastName = 'EventRelay Ingest Smoke ' +
                        record.get('Message__c', String.class),
                    Description = 'handlerUser=' + UserInfo.getUserName()
                )
            );
        }

        insert contacts;
    }
}
