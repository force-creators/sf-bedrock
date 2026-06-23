/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class AsyncFilters {
    public static Boolean shouldRetry(
        List<Async__c> records,
        Map<Id, Async__c> oldMap
    ) {
        for (Async__c record : records) {
            if (
                record.Status__c == Async.consts.PENDING &&
                oldMap.get(record.Id).Status__c == Async.consts.ERROR
            ) {
                return true;
            }
        }
        return false;
    }
}
