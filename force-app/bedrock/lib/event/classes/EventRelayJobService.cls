/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class EventRelayJobService {
    @testVisible
    EventRelay.PublishWatcher watcher;
    @testVisible
    EventRelay.ProcessWatcher processWatcher;

    public virtual void enqueue(List<Event__c> workItems) {
        if (workItems == null || workItems.isEmpty())
            return;

        EventRelay.wakeSignal.signal();
    }

    public virtual void enqueueNextPublishJob(Id threadId, Integer failures) {
        enqueueNextPublishJob(
            threadId,
            failures,
            Thread.service.currentRunKey(threadId)
        );
    }

    public virtual void enqueueNextPublishJob(
        Id threadId,
        Integer failures,
        String runKey
    ) {
        enqueueNextJob(threadId, failures, runKey, EventRelay.consts.PUBLISH);
    }

    public virtual void enqueueNextProcessJob(Id threadId, Integer failures) {
        enqueueNextProcessJob(
            threadId,
            failures,
            Thread.service.currentRunKey(threadId)
        );
    }

    public virtual void enqueueNextProcessJob(
        Id threadId,
        Integer failures,
        String runKey
    ) {
        enqueueNextJob(threadId, failures, runKey, EventRelay.consts.PROCESS);
    }

    void enqueueNextJob(
        Id threadId,
        Integer failures,
        String runKey,
        String jobType
    ) {
        List<Event__c> workItems = jobType == EventRelay.consts.PROCESS
            ? EventRelay.queries.getPendingProcessWorkItems(
                  threadId,
                  EventRelay.settings.batchSize()
              )
            : EventRelay.queries.getPendingWorkItems(
                  threadId,
                  EventRelay.settings.batchSize()
              );
        if (workItems.isEmpty()) {
            Thread.continueCurrent(failures, runKey);
            return;
        }

        List<Id> workItemIds = idsFrom(workItems);
        if (!Thread.service.canStartQueueableWork()) {
            Thread.pause(
                threadId,
                Thread.service.queueablePauseReason(),
                runKey
            );
            return;
        }

        if (
            jobType == EventRelay.consts.PUBLISH &&
            EventRelay.publishers.requiresPlatformEventLimit(workItems) &&
            !Limiter.isSafe(
                Limiter.types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS,
                EventRelay.settings.limitThresholdPct()
            )
        ) {
            Thread.pause(
                threadId,
                'Platform Event publication limit is not safe.',
                runKey
            );
            return;
        }

        EventRelay.work.running(new Set<Id>(workItemIds));
        if (jobType == EventRelay.consts.PROCESS) {
            new EventRelay.ProcessJob(threadId, workItemIds, failures, runKey)
                .enqueue();
            return;
        }
        new EventRelay.PublishJob(threadId, workItemIds, failures, runKey)
            .enqueue();
    }

    public virtual EventRelay.PublishWatcher watch(
        Id threadId,
        List<Id> workItemIds,
        Integer failures,
        String runKey
    ) {
        watcher = new EventRelay.PublishWatcher(
            threadId,
            workItemIds,
            failures,
            runKey
        );
        return watcher;
    }

    public virtual EventRelay.ProcessWatcher watchProcess(
        Id threadId,
        List<Id> workItemIds,
        Integer failures,
        String runKey
    ) {
        processWatcher = new EventRelay.ProcessWatcher(
            threadId,
            workItemIds,
            failures,
            runKey
        );
        return processWatcher;
    }

    public virtual void attachFinalizer(Finalizer finalizer) {
        System.attachFinalizer(finalizer);
    }

    List<Id> idsFrom(List<Event__c> workItems) {
        List<Id> ids = new List<Id>();
        for (Event__c workItem : workItems)
            ids.add(workItem.Id);
        return ids;
    }
}
