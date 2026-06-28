/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class EventRelayPublishSmokePublisher extends EventRelay.Publisher {
    public override void execute(List<SObject> records) {
        List<SObject> contacts = new List<SObject>();
        for (SObject record : records) {
            contacts.add(
                new Contact(
                    LastName = 'EventRelay Publish Smoke ' +
                        String.valueOf(record.get('Message__c')),
                    Description = 'publisherUser=' + UserInfo.getUserName()
                )
            );
        }

        insert contacts;
    }
}
