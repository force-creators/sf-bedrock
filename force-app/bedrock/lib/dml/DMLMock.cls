/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public inherited sharing class DMLMock extends DML.Service {
    public List<List<SObject>> inserts = new List<List<SObject>>();
    public List<List<SObject>> updates = new List<List<SObject>>();
    public List<List<SObject>> upserts = new List<List<SObject>>();
    public List<List<SObject>> deletes = new List<List<SObject>>();
    public List<List<SObject>> undeletes = new List<List<SObject>>();

    public override void insertRecords(List<SObject> records) {
        this.inserts.add(records);
    }

    public override void updateRecords(List<SObject> records) {
        this.updates.add(records);
    }

    public override void upsertRecords(List<SObject> records) {
        this.upserts.add(records);
    }

    public override void upsertRecords(
        List<SObject> records,
        SObjectField externalIdField
    ) {
        this.upserts.add(records);
    }

    public override void deleteRecords(List<SObject> records) {
        this.deletes.add(records);
    }

    public override void undeleteRecords(List<SObject> records) {
        this.undeletes.add(records);
    }
}
