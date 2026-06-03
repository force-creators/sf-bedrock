public virtual inherited sharing class Query {
    static Query instance = new Query();
    
    @testvisible static void setMock(Query mock) {
        instance = mock;
    }

    public virtual List<SObject> query(List<SObject> records) {
        return records;
    }

    public static List<SObject> records(List<SObject> records) {
        return instance.query(records);
    }
}