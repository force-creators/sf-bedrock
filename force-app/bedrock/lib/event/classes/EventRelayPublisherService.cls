/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class EventRelayPublisherService {
  public virtual EventRelay.Publisher forWorkItems(List<Event__c> workItems) {
    if (workItems == null || workItems.isEmpty())
      return new EventRelay.Publisher();

    String publisherClass = workItems[0].Apex__c;
    for (Event__c workItem : workItems) {
      if (workItem.Apex__c != publisherClass) {
        throw new EventRelay.EventRelayException(
          'A publish batch can only contain one publisher class.'
        );
      }
    }
    return forClass(publisherClass);
  }

  public virtual Boolean requiresPlatformEventLimit(List<Event__c> workItems) {
    if (workItems == null || workItems.isEmpty())
      return false;

    String publisherClass = workItems[0].Apex__c;
    return String.isBlank(publisherClass) ||
      publisherClass == EventRelay.consts.PLATFORM_EVENT_PUBLISHER;
  }

  public virtual EventRelay.Publisher forClass(String publisherClass) {
    String safePublisherClass = String.isBlank(publisherClass)
      ? EventRelay.consts.PLATFORM_EVENT_PUBLISHER
      : publisherClass.trim();
    if (safePublisherClass == EventRelay.consts.PLATFORM_EVENT_PUBLISHER) {
      return new EventRelay.PlatformEventPublisher();
    }

    Type publisherType = Type.forName(safePublisherClass);
    if (publisherType == null) {
      throw new EventRelay.EventRelayException(
        'Unknown EventRelay publisher class ' + safePublisherClass + '.'
      );
    }

    Object publisherInstance = publisherType.newInstance();
    if (!(publisherInstance instanceof EventRelay.Publisher)) {
      throw new EventRelay.EventRelayException(
        safePublisherClass + ' must extend EventRelay.Publisher.'
      );
    }
    return (EventRelay.Publisher) publisherInstance;
  }
}
