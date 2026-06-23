/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class Pluck {
  public static Set<Id> ids(List<SObject> records) {
    Set<Id> ids = new Set<Id>();
    for (SObject record : records) {
      if (record.Id != null)
        ids.add(record.Id);
    }
    return ids;
  }

  public static Set<Id> ids(SObjectField field, List<SObject> records) {
    Set<Id> ids = new Set<Id>();
    for (SObject record : records) {
      if (record.get(field) != null)
        ids.add((Id) record.get(field));
    }
    return ids;
  }
}
