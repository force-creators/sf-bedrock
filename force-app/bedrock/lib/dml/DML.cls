/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual inherited sharing class DML extends Service {
  static Service instance = new Service();

  @testvisible
  static void setMock(Service mock) {
    instance = mock;
  }

  public static void insertRecords(List<SObject> records) {
    instance.insertRecords(records);
  }

  public static void updateRecords(List<SObject> records) {
    instance.updateRecords(records);
  }

  public static void upsertRecords(List<SObject> records) {
    instance.upsertRecords(records);
  }

  public static void upsertRecords(
    List<SObject> records,
    SObjectField externalIdField
  ) {
    instance.upsertRecords(records, externalIdField);
  }

  public static void deleteRecords(List<SObject> records) {
    instance.deleteRecords(records);
  }

  public static void undeleteRecords(List<SObject> records) {
    instance.undeleteRecords(records);
  }

  public virtual inherited sharing class Service implements Contract {
    public virtual void insertRecords(List<SObject> records) {
      insert records;
    }

    public virtual void updateRecords(List<SObject> records) {
      update records;
    }

    public virtual void upsertRecords(List<SObject> records) {
      upsert records;
    }

    public virtual void upsertRecords(
      List<SObject> records,
      SObjectField externalIdField
    ) {
      Database.upsert(records, externalIdField, true);
    }

    public virtual void deleteRecords(List<SObject> records) {
      delete records;
    }

    public virtual void undeleteRecords(List<SObject> records) {
      undelete records;
    }
  }

  public interface Contract {
    void insertRecords(List<SObject> records);
    void updateRecords(List<SObject> records);
    void upsertRecords(List<SObject> records);
    void upsertRecords(List<SObject> records, SObjectField externalIdField);
    void deleteRecords(List<SObject> records);
    void undeleteRecords(List<SObject> records);
  }
}
