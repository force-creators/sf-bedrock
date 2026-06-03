public with sharing class TestData {
    static IdService idService = new IdService();

    SObjectType sObjectType;
    Map<SObjectField, Object> template = new Map<SObjectField, Object>();
    Integer count = 1;
    Boolean mockids = false;

    public TestData(SObjectType sObjectType) {
        this.sObjectType = sObjectType;
    }

    public TestData mockIds() {
        this.mockids = true;
        return this;
    }

    public TestData put(SObjectField field, Object value) {
        template.put(field, value);
        return this;
    }

    public TestData count(Integer count) {
        this.count = count;
        return this;
    }

    public List<SObject> build() {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        for(Integer i = 0; i < this.count; i++) {
            Map<String, Object> record = new Map<String, Object> {
                'attributes' => new Map<String, Object> {
                    'type' => sObjectType.getDescribe().getName()
                }
            };
            for(SObjectField field : this.template.keySet()) {
                Object value = this.template.get(field);
                if(value instanceof SObject) {
                    SObject mergeRecord = (SObject) this.template.get(field);
                    record.put(String.valueOf(field), mergeRecord.Id);
                    record.put(field.getDescribe().getRelationshipName(), mergeRecord);
                } else {
                    record.put(String.valueOf(field), this.template.get(field));
                }
            }
            if(this.mockids) record.put('id', idService.get(this.sObjectType));
            records.add(record);
        }
        List<SObject> results = (List<SObject>) JSON.deserialize(JSON.serialize(records), List<SObject>.class);
        return results;
    }

    public with sharing class IdService {
        Map<SObjectType, Integer> idIndex = new Map<SObjectType, Integer>();
        public Id get(SObjectType sObjectType) {
            Integer index = idIndex.get(sObjectType);
            if(index == null) index = 0;
            index++;

            String pointer = String.valueOf(index);
            Id result = sObjectType.getDescribe().getKeyPrefix() + '0'.repeat(12-pointer.length()) + pointer;
            idIndex.put(sObjectType, index);
            return result;
        }
    }
}