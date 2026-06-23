/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class BedrockConsoleSupport {
  public static String normalizeSearchTerm(String searchTerm) {
    return String.isBlank(searchTerm) ? null : searchTerm.trim().toLowerCase();
  }

  public static String sortOrder(String sortDirection) {
    return String.isBlank(sortDirection)
      ? 'DESC'
      : (sortDirection.toLowerCase() == 'asc' ? 'ASC' : 'DESC');
  }

  public static Boolean containsIgnoreCase(String value, String searchTerm) {
    return value != null &&
      searchTerm != null &&
      value.toLowerCase().contains(searchTerm);
  }

  public static String preview(String value, Integer maxLength) {
    if (String.isBlank(value))
      return null;
    if (maxLength == null || maxLength < 4 || value.length() <= maxLength)
      return value;
    return value.left(maxLength - 3) + '...';
  }

  public static Map<Id, Thread__c> asyncThreadsById(List<Async__c> workItems) {
    Set<Id> threadIds = new Set<Id>();
    for (Async__c workItem : workItems) {
      if (workItem.Thread__c != null) {
        threadIds.add(workItem.Thread__c);
      }
    }

    return threadIds.isEmpty()
      ? new Map<Id, Thread__c>()
      : new Map<Id, Thread__c>(
          [
            SELECT Id, Name
            FROM Thread__c
            WHERE Id IN :threadIds
          ]
        );
  }

  public static String asyncThreadLabel(
    Async__c workItem,
    Map<Id, Thread__c> threadsById,
    String fallback
  ) {
    if (
      workItem.Thread__c == null || !threadsById.containsKey(workItem.Thread__c)
    )
      return fallback;
    return threadsById.get(workItem.Thread__c).Name;
  }

  public static Integer compareValues(Object leftValue, Object rightValue) {
    if (leftValue == rightValue)
      return 0;
    if (leftValue == null)
      return -1;
    if (rightValue == null)
      return 1;
    if (leftValue instanceof Datetime) {
      Long leftTime = ((Datetime) leftValue).getTime();
      Long rightTime = ((Datetime) rightValue).getTime();
      if (leftTime == rightTime)
        return 0;
      return leftTime < rightTime ? -1 : 1;
    }
    return String.valueOf(leftValue)
      .toLowerCase()
      .compareTo(String.valueOf(rightValue).toLowerCase());
  }
}
