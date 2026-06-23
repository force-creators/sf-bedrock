/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class AsyncArchiveBatch implements Database.Batchable<SObject>, Database.Stateful {
  Set<Id> archivedThreadIds = new Set<Id>();

  public Database.QueryLocator start(Database.BatchableContext context) {
    Datetime archiveBefore = System.now()
      .addHours(-Async.settings.archiveThresholdHours());
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Apex__c,
          Error_Message__c,
          Error_Stack_Trace__c,
          Name,
          Priority__c,
          Record_Id__c,
          Retry_Count__c,
          Status__c,
          Thread__c,
          Thread__r.Name
        FROM Async__c
        WHERE Status__c = 'Done' AND CreatedDate <= :archiveBefore
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (scope == null || scope.isEmpty())
      return;

    List<SObject> archives = new List<SObject>();
    List<SObject> workItems = new List<SObject>();
    for (SObject record : scope) {
      Async__c workItem = (Async__c) record;
      archives.add(archiveFrom(workItem));
      workItems.add(workItem);
      if (workItem.Thread__c != null) {
        archivedThreadIds.add(workItem.Thread__c);
      }
    }

    DML.insertRecords(archives);
    DML.deleteRecords(workItems);
  }

  public void finish(Database.BatchableContext context) {
    Thread.deleteDrained(archivedThreadIds);
    if (Async.settings.archiveCleanupEnabled()) {
      Database.executeBatch(new AsyncArchiveCleanupBatch(), 200);
    }
  }

  Async_Archive__c archiveFrom(Async__c workItem) {
    return new Async_Archive__c(
      Apex__c = workItem.Apex__c,
      Error_Message__c = workItem.Error_Message__c,
      Error_Stack_Trace__c = workItem.Error_Stack_Trace__c,
      Priority__c = workItem.Priority__c,
      Record_Id__c = workItem.Record_Id__c,
      Retry_Count__c = workItem.Retry_Count__c,
      Status__c = workItem.Status__c,
      Thread__c = workItem.Thread__r == null ? null : workItem.Thread__r.Name
    );
  }
}
