/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:AsyncCompletedController')
public with sharing class AsyncCompletedControllerTest {
    @istest
    static void testGetCompleted_returnsDoneRowsForMvp() {
        Thread__c completedThread = new Thread__c(Status__c = 'Done');
        Thread__c errorThread = new Thread__c(Status__c = 'Done');
        insert new List<Thread__c>{ completedThread, errorThread };
        completedThread = [
            SELECT Name
            FROM Thread__c
            WHERE Id = :completedThread.Id
        ];

        DML.insertRecords(
            new List<SObject>{
                workItem(
                    'CompletedJob',
                    '001000000000001AAA',
                    'Done',
                    completedThread.Id
                ),
                workItem(
                    'IgnoredError',
                    '001000000000002AAA',
                    'Error',
                    errorThread.Id
                )
            }
        );

        Test.startTest();
        List<AsyncCompletedController.CompletedRow> rows = AsyncCompletedController.getCompleted(
            null,
            null,
            null
        );
        Test.stopTest();

        Assert.areEqual(
            1,
            rows.size(),
            'Expected the completed tab query to return only Done work items.'
        );
        Assert.isNotNull(
            rows[0].asyncJobNumber,
            'Expected the completed row to include the async job number.'
        );
        Assert.areEqual(
            'CompletedJob',
            rows[0].apexClass,
            'Expected the completed row to include the Apex class.'
        );
        Assert.areEqual(
            '001000000000001AAA',
            rows[0].recordId,
            'Expected the completed row to include the record id.'
        );
        Assert.areEqual(
            completedThread.Name,
            rows[0].thread,
            'Expected the completed row to include the thread name.'
        );
        Assert.isNotNull(
            rows[0].createdDate,
            'Expected the completed row to include the created date for MVP ordering.'
        );
    }

    @istest
    static void testGetCompleted_appliesSearchAndSort() {
        Thread__c firstThread = new Thread__c(Status__c = 'Done');
        Thread__c secondThread = new Thread__c(Status__c = 'Done');
        insert new List<Thread__c>{ firstThread, secondThread };

        DML.insertRecords(
            new List<SObject>{
                workItem(
                    'ZebraJob',
                    '001000000000003AAA',
                    'Done',
                    firstThread.Id
                ),
                workItem(
                    'AlphaJob',
                    '001000000000004AAA',
                    'Done',
                    secondThread.Id
                )
            }
        );

        Test.startTest();
        List<AsyncCompletedController.CompletedRow> filteredRows = AsyncCompletedController.getCompleted(
            'Alpha',
            'apexClass',
            'asc'
        );
        List<AsyncCompletedController.CompletedRow> sortedRows = AsyncCompletedController.getCompleted(
            null,
            'apexClass',
            'asc'
        );
        Test.stopTest();

        Assert.areEqual(
            1,
            filteredRows.size(),
            'Expected the completed tab filter to match Apex, record id, thread, or job number text.'
        );
        Assert.areEqual(
            'AlphaJob',
            filteredRows[0].apexClass,
            'Expected the filtered result to keep the matching row.'
        );

        Assert.areEqual(
            'AlphaJob',
            sortedRows[0].apexClass,
            'Expected sorting to honor the requested ascending class order.'
        );
        Assert.areEqual(
            'ZebraJob',
            sortedRows[1].apexClass,
            'Expected sorting to include the second row after the first.'
        );
    }

    static Async__c workItem(
        String apexClass,
        String recordId,
        String status,
        Id threadId
    ) {
        Async__c workItem = new Async__c(
            Apex__c = apexClass,
            Record_Id__c = recordId,
            Status__c = status
        );
        workItem.put('Thread__c', threadId);
        return workItem;
    }
}
