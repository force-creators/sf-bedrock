/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class EventRelayQueryService {
    public virtual List<Event__c> getPendingWorkItems(
        Id threadId,
        Integer batchSize
    ) {
        return getPendingWorkItems(
            threadId,
            batchSize,
            EventRelay.consts.PUBLISH
        );
    }

    public virtual List<Event__c> getPendingProcessWorkItems(
        Id threadId,
        Integer batchSize
    ) {
        return getPendingWorkItems(
            threadId,
            batchSize,
            EventRelay.consts.PROCESS
        );
    }

    public virtual List<Event__c> getPendingWorkItems(
        Id threadId,
        Integer batchSize,
        String jobType
    ) {
        Integer safeBatchSize = batchSize == null ||
            batchSize < 1
            ? EventRelay.settings.batchSize()
            : batchSize;
        String safeJobType = String.isBlank(jobType)
            ? EventRelay.consts.PUBLISH
            : jobType.trim();
        List<Event__c> heads = (List<Event__c>) Query.records(
            Database.query(
                'SELECT Id, Payload_Type__c, Payload1__c, Payload2__c, Payload3__c, Payload4__c ' +
                    ', Apex__c, Route__c, Retry_Count__c ' +
                    'FROM Event__c ' +
                    'WHERE Thread__c = :threadId ' +
                    'AND Job_Type__c = :safeJobType ' +
                    'AND Status__c = \'Pending\' ' +
                    'ORDER BY CreatedDate ASC, Order__c ASC, Name ASC ' +
                    'LIMIT 1'
            )
        );
        if (heads.isEmpty())
            return new List<Event__c>();

        Event__c head = heads[0];
        safeBatchSize = EventRelay.metadata.batchSize(
            head.Route__c,
            safeBatchSize
        );

        List<Event__c> workItems = (List<Event__c>) Query.records(
            Database.query(
                'SELECT Id, Payload_Type__c, Payload1__c, Payload2__c, Payload3__c, Payload4__c ' +
                    ', Apex__c, Route__c, Retry_Count__c ' +
                    'FROM Event__c ' +
                    'WHERE Thread__c = :threadId ' +
                    'AND Job_Type__c = :safeJobType ' +
                    'AND Status__c = \'Pending\' ' +
                    'ORDER BY CreatedDate ASC, Order__c ASC, Name ASC ' +
                    'LIMIT :safeBatchSize'
            )
        );
        return firstCompatibleBatch(workItems);
    }

    public virtual Boolean hasPendingWork(Id threadId) {
        return !getPendingWorkItems(threadId, 1).isEmpty();
    }

    public virtual Boolean hasRecoverableWork(Id threadId) {
        return hasPendingWork(threadId) ||
            !getRunningWorkItemIds(threadId).isEmpty();
    }

    public virtual Set<Id> getPendingWorkItemIds(
        Id threadId,
        Integer batchSize
    ) {
        Set<Id> workItemIds = new Set<Id>();
        for (Event__c workItem : getPendingWorkItems(threadId, batchSize))
            workItemIds.add(workItem.Id);
        return workItemIds;
    }

    public virtual Set<Id> getRunningWorkItemIds(Id threadId) {
        return getRunningWorkItemIds(threadId, EventRelay.consts.PUBLISH);
    }

    public virtual Set<Id> getRunningWorkItemIds(Id threadId, String jobType) {
        Set<Id> workItemIds = new Set<Id>();
        String safeJobType = String.isBlank(jobType)
            ? EventRelay.consts.PUBLISH
            : jobType.trim();
        String runningStatus = EventRelay.consts.RUNNING;
        for (
            Event__c workItem : (List<Event__c>) Query.records(
                [
                    SELECT Id
                    FROM Event__c
                    WHERE
                        Thread__c = :threadId
                        AND Job_Type__c = :safeJobType
                        AND Status__c = :runningStatus
                ]
            )
        ) {
            workItemIds.add(workItem.Id);
        }
        return workItemIds;
    }

    public virtual List<Event__c> getWorkItemsById(List<Id> workItemIds) {
        if (workItemIds == null || workItemIds.isEmpty())
            return new List<Event__c>();

        Map<Id, Event__c> workItemsById = new Map<Id, Event__c>(
            (List<Event__c>) Query.records(
                [
                    SELECT
                        Id,
                        Apex__c,
                        Route__c,
                        Payload_Type__c,
                        Retry_Count__c,
                        Payload1__c,
                        Payload2__c,
                        Payload3__c,
                        Payload4__c
                    FROM Event__c
                    WHERE Id IN :workItemIds
                ]
            )
        );

        List<Event__c> orderedWorkItems = new List<Event__c>();
        for (Id workItemId : workItemIds) {
            if (workItemsById.containsKey(workItemId))
                orderedWorkItems.add(workItemsById.get(workItemId));
        }
        return orderedWorkItems;
    }

    public virtual List<Event__c> getWorkItemsById(Set<Id> workItemIds) {
        return getWorkItemsById(new List<Id>(workItemIds));
    }

    public virtual List<Event__c> getRetryableWorkItems(Set<Id> workItemIds) {
        if (workItemIds == null || workItemIds.isEmpty())
            return new List<Event__c>();

        String errorStatus = EventRelay.consts.ERROR;
        return (List<Event__c>) Query.records(
            [
                SELECT Id, Thread__c
                FROM Event__c
                WHERE Id IN :workItemIds AND Status__c = :errorStatus
                ORDER BY CreatedDate ASC, Order__c ASC, Name ASC
            ]
        );
    }

    public virtual Map<String, Event__c> getAcceptedWorkByIdempotencyKey(
        List<Event__c> candidates
    ) {
        Map<String, Event__c> workByKey = new Map<String, Event__c>();
        if (candidates == null || candidates.isEmpty())
            return workByKey;

        Set<String> idempotencyKeys = new Set<String>();
        Set<String> lookupKeys = new Set<String>();
        for (Event__c candidate : candidates) {
            if (String.isBlank(candidate.Idempotency_Key__c))
                continue;

            idempotencyKeys.add(candidate.Idempotency_Key__c);
            lookupKeys.add(idempotencyLookupKey(candidate));
        }
        if (idempotencyKeys.isEmpty())
            return workByKey;

        Set<String> acceptedStatuses = new Set<String>{
            EventRelay.consts.PENDING,
            EventRelay.consts.RUNNING,
            EventRelay.consts.DONE
        };
        for (
            Event__c workItem : (List<Event__c>) Query.records(
                [
                    SELECT Id, Job_Type__c, Route__c, Idempotency_Key__c
                    FROM Event__c
                    WHERE
                        Idempotency_Key__c IN :idempotencyKeys
                        AND Status__c IN :acceptedStatuses
                    ORDER BY CreatedDate ASC, Order__c ASC, Name ASC
                ]
            )
        ) {
            String lookupKey = idempotencyLookupKey(workItem);
            if (
                lookupKeys.contains(lookupKey) &&
                !workByKey.containsKey(lookupKey)
            ) {
                workByKey.put(lookupKey, workItem);
            }
        }
        return workByKey;
    }

    List<Event__c> firstCompatibleBatch(List<Event__c> workItems) {
        List<Event__c> batch = new List<Event__c>();
        if (workItems == null || workItems.isEmpty())
            return batch;

        Event__c head = workItems[0];
        for (Event__c workItem : workItems) {
            if (
                workItem.Apex__c != head.Apex__c ||
                workItem.Route__c != head.Route__c ||
                workItem.Payload_Type__c != head.Payload_Type__c
            ) {
                break;
            }
            batch.add(workItem);
        }
        return batch;
    }

    String idempotencyLookupKey(Event__c workItem) {
        return JSON.serialize(
            new List<String>{
                workItem.Job_Type__c,
                workItem.Route__c,
                workItem.Idempotency_Key__c
            }
        );
    }
}
