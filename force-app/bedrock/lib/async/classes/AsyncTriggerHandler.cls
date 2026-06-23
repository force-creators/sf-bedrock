/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class AsyncTriggerHandler extends TriggerHandler {
  public override void afterInsert(List<SObject> newRecords) {
    Async.jobs.enqueue((List<Async__c>) newRecords);
  }

  public override void afterUpdate(
    List<SObject> records,
    Map<Id, SObject> old
  ) {
    List<Async__c> newRecords = (List<Async__c>) records;
    Map<Id, Async__c> oldMap = (Map<Id, Async__c>) old;

    if (AsyncFilters.shouldRetry(newRecords, oldMap)) {
      Async.jobs.enqueue(newRecords);
    }
  }
}
