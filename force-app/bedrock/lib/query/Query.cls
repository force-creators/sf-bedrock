/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual inherited sharing class Query {
  static Query instance = new Query();

  @testvisible
  static void setMock(Query mock) {
    instance = mock;
  }

  public virtual List<SObject> query(List<SObject> records) {
    return records;
  }

  public static List<SObject> records(List<SObject> records) {
    return instance.query(records);
  }
}
