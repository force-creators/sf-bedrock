/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest
class EventRelayEndToEndSmokeTest {
  @istest
  static void publish_customPublisher_runsAndCompletesWork() {
    resetSeams();

    List<Id> workItemIds = EventRelay.publish(
      new List<SObject>{ new Bedrock_Test_Event__e(Message__c = 'publish') },
      EventRelayPublishSmokePublisher.class
    );
    Event__c workItem = workItem(workItemIds[0]);
    String runKey = Thread.service.startRun(workItem.Thread__c);

    Test.startTest();
    new EventRelay.PublishJob(workItem.Thread__c, workItemIds, 0, runKey)
      .enqueue();
    Test.stopTest();

    Event__c completedWorkItem = workItem(workItemIds[0]);
    Assert.areEqual(
      EventRelay.consts.DONE,
      completedWorkItem.Status__c,
      'Expected custom publisher smoke work to complete successfully.'
    );

    List<Contact> contacts = [
      SELECT LastName, Description
      FROM Contact
      WHERE LastName = 'EventRelay Publish Smoke publish'
    ];
    Assert.areEqual(
      1,
      contacts.size(),
      'Expected the smoke publisher to create one contact as a publication side effect.'
    );
    Assert.isTrue(
      contacts[0].Description.contains('publisherUser='),
      'Expected the smoke publisher to run inside EventRelay publication work.'
    );
  }

  @istest
  static void ingest_platformEventHandler_runsAndCompletesWork() {
    resetSeams();

    List<Id> workItemIds = EventRelay.ingest(
      new List<SObject>{ new Bedrock_Test_Event__e(Message__c = 'ingest') },
      EventRelayIngestSmokeHandler.class
    );
    Event__c workItem = workItem(workItemIds[0]);
    String runKey = Thread.service.startRun(workItem.Thread__c);

    Test.startTest();
    new EventRelay.ProcessJob(workItem.Thread__c, workItemIds, 0, runKey)
      .enqueue();
    Test.stopTest();

    Event__c completedWorkItem = workItem(workItemIds[0]);
    Assert.areEqual(
      EventRelay.consts.DONE,
      completedWorkItem.Status__c,
      'Expected ingest smoke work to complete successfully.'
    );

    List<Contact> contacts = [
      SELECT LastName, Description
      FROM Contact
      WHERE LastName = 'EventRelay Ingest Smoke ingest'
    ];
    Assert.areEqual(
      1,
      contacts.size(),
      'Expected the smoke handler to create one contact as an ingest side effect.'
    );
    Assert.isTrue(
      contacts[0].Description.contains('handlerUser='),
      'Expected the smoke handler to run inside EventRelay process work.'
    );
  }

  @istest
  static void ingest_genericHandler_runsAndCompletesWork() {
    resetSeams();

    List<Id> workItemIds = EventRelay.ingest(
      new List<Generic>{
        new Generic(new Map<String, Object>{ 'Message__c' => 'generic' })
      },
      EventRelayIngestSmokeHandler.class
    );
    Event__c workItem = workItem(workItemIds[0]);
    String runKey = Thread.service.startRun(workItem.Thread__c);

    Test.startTest();
    new EventRelay.ProcessJob(workItem.Thread__c, workItemIds, 0, runKey)
      .enqueue();
    Test.stopTest();

    Event__c completedWorkItem = workItem(workItemIds[0]);
    Assert.areEqual(
      EventRelay.consts.DONE,
      completedWorkItem.Status__c,
      'Expected generic ingest smoke work to complete successfully.'
    );

    List<Contact> contacts = [
      SELECT LastName
      FROM Contact
      WHERE LastName = 'EventRelay Ingest Smoke generic'
    ];
    Assert.areEqual(
      1,
      contacts.size(),
      'Expected the smoke handler to process generic payloads.'
    );
  }

  static void resetSeams() {
    EventRelay.reset();
    ThreadRunner.reset();
    DML.setMock(new DML.Service());
    Query.setMock(new Query());
  }

  static Event__c workItem(Id workItemId) {
    return [
      SELECT Id, Status__c, Thread__c
      FROM Event__c
      WHERE Id = :workItemId
      LIMIT 1
    ];
  }
}
