/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:ThreadDashboardController')
public with sharing class ThreadDashboardControllerTest {
    @istest
    static void testGetMetrics_countsThreadStates() {
        Datetime now = System.now();
        Thread.settings.setSettings(
            new Thread_Settings__c(Recovery_Threshold_Minutes__c = 10)
        );
        DML.insertRecords(
            new List<SObject>{
                thread(Thread.consts.RUNNING, now.addMinutes(-1), null),
                thread(Thread.consts.PENDING, now.addMinutes(-20), null),
                thread(Thread.consts.DONE, now.addMinutes(-30), now)
            }
        );

        Test.startTest();
        ThreadDashboardController.DashboardMetrics metrics = ThreadDashboardController.getMetrics();
        Test.stopTest();

        Assert.areEqual(
            1,
            metrics.runningThreads,
            'Expected metrics to count running thread records.'
        );
        Assert.areEqual(
            1,
            metrics.pendingThreads,
            'Expected metrics to count pending thread records.'
        );
        Assert.areEqual(
            1,
            metrics.staleThreads,
            'Expected metrics to count non-done threads past the recovery heartbeat threshold.'
        );
        Assert.areEqual(
            1,
            metrics.completedToday,
            'Expected metrics to count threads completed today.'
        );
    }

    static Thread__c thread(
        String status,
        Datetime heartbeatAt,
        Datetime completedAt
    ) {
        return new Thread__c(
            Status__c = status,
            Pool__c = Thread.consts.ASYNC_POOL,
            Thread_Key__c = 'request:' + status,
            Heartbeat__c = heartbeatAt,
            Completed__c = completedAt
        );
    }
}
