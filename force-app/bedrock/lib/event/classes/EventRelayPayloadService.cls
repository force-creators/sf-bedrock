public virtual with sharing class EventRelayPayloadService {
    public virtual String serialize(SObject eventRecord) {
        return JSON.serialize(eventRecord.getPopulatedFieldsAsMap());
    }

    public virtual List<SObject> toSObjects(List<Event__c> workItems) {
        List<SObject> events = new List<SObject>();
        if (workItems == null) return events;

        for (Event__c workItem : workItems) events.add(toSObject(workItem));
        return events;
    }

    public virtual List<EventRelay.PublishPayload> toPublishPayloads(List<Event__c> workItems) {
        List<EventRelay.PublishPayload> publishPayloads = new List<EventRelay.PublishPayload>();
        if (workItems == null) return publishPayloads;

        for (Event__c workItem : workItems) {
            publishPayloads.add(new EventRelay.PublishPayload(
                workItem.Id,
                workItem.Route__c,
                workItem.Payload_Type__c,
                toGeneric(workItem)
            ));
        }
        return publishPayloads;
    }

    public virtual List<SObject> toPlatformEvents(List<EventRelay.PublishPayload> publishPayloads) {
        List<SObject> events = new List<SObject>();
        if (publishPayloads == null) return events;

        for (EventRelay.PublishPayload publishPayload : publishPayloads) events.add(toSObject(publishPayload));
        return events;
    }

    public virtual List<Generic> toGenericList(List<EventRelay.PublishPayload> publishPayloads) {
        List<Generic> records = new List<Generic>();
        if (publishPayloads == null) return records;

        for (EventRelay.PublishPayload publishPayload : publishPayloads) records.add(publishPayload.payload);
        return records;
    }

    public virtual List<Generic> toGenericEvents(List<Event__c> workItems) {
        List<Generic> records = new List<Generic>();
        if (workItems == null) return records;

        for (Event__c workItem : workItems) records.add(toGeneric(workItem));
        return records;
    }

    public virtual SObject toSObject(Event__c workItem) {
        return toSObject(new EventRelay.PublishPayload(
            workItem.Id,
            workItem.Route__c,
            workItem.Payload_Type__c,
            toGeneric(workItem)
        ));
    }

    public virtual SObject toSObject(EventRelay.PublishPayload publishPayload) {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(publishPayload.payloadType);
        if (sObjectType == null) {
            throw new EventRelay.EventRelayException('Unknown platform event type ' + publishPayload.payloadType + '.');
        }

        SObject eventRecord = sObjectType.newSObject();
        Map<String, Object> values = publishPayload.payload.generic();
        Map<String, Schema.SObjectField> fields = sObjectType.getDescribe().fields.getMap();
        for (String fieldName : values.keySet()) {
            if (fields.containsKey(fieldName)) {
                eventRecord.put(fieldName, values.get(fieldName));
            }
        }
        return eventRecord;
    }

    public virtual Generic toGeneric(Event__c workItem) {
        return new Generic(read(workItem));
    }

    public virtual void write(Event__c workItem, String payload) {
        if (payload == null) payload = '';
        if (payload.length() > chunkSize() * 4) {
            throw new EventRelay.EventRelayException('Event payload exceeds EventRelay storage capacity.');
        }

        workItem.Payload1__c = chunk(payload, 0);
        workItem.Payload2__c = chunk(payload, 1);
        workItem.Payload3__c = chunk(payload, 2);
        workItem.Payload4__c = chunk(payload, 3);
    }

    public virtual String read(Event__c workItem) {
        return value(workItem.Payload1__c)
            + value(workItem.Payload2__c)
            + value(workItem.Payload3__c)
            + value(workItem.Payload4__c);
    }

    Integer chunkSize() {
        return 32768;
    }

    String chunk(String value, Integer index) {
        Integer startIndex = chunkSize() * index;
        if (value.length() <= startIndex) return null;

        Integer endIndex = Math.min(value.length(), startIndex + chunkSize());
        return value.substring(startIndex, endIndex);
    }

    String value(String text) {
        return text == null ? '' : text;
    }
}
