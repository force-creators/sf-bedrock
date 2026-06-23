/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual inherited sharing class QueryMock extends Query {
    List<SObject> records;

    public QueryMock() {
    } // Default constructor
    public QueryMock(SObject record) {
        this(new List<SObject>{ record });
    }
    public QueryMock(List<SObject> records) {
        this.records = records;
    }

    public virtual override List<SObject> query(List<SObject> ignore) {
        return records;
    }

    public inherited sharing class Multiple extends QueryMock {
        List<List<SObject>> records = new List<List<SObject>>();
        Integer index = 0;

        public Multiple() {
        }

        public Multiple add(List<SObject> records) {
            this.records.add(records);
            return this;
        }

        public override List<SObject> query(List<SObject> ignore) {
            if (index >= records.size()) {
                throw new QueryMockException('No more records to return');
            }
            return records[index++];
        }
    }

    public class QueryMockException extends Exception {
    }
}
