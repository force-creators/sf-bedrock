/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class RecordBufferMock {
    public DmlService dml;

    public RecordBufferMock() {
        dml = new DmlService();
    }

    public RecordBufferMock mockDml() {
        dml.mockDml();
        return this;
    }

    public with sharing class DmlService extends RecordBuffer.DmlService {
        public List<List<SObject>> upserts = new List<List<SObject>>();
        public Boolean useMockDml = false;

        public DmlService mockDml() {
            this.useMockDml = true;
            return this;
        }

        public override void upsertRecords(List<SObject> records) {
            this.upserts.add(records);
            if (!this.useMockDml) {
                super.upsertRecords(records);
            }
        }
    }
}
