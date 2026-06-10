public virtual with sharing class Async implements Queueable, Database.AllowsCallouts {
    public static JobService jobs = new JobService();
    public static WorkService work = new WorkService();
    public static QueryService queries = new QueryService();

    @testVisible static void setMock(AsyncMock mock) {
        jobs = mock.jobs;
        work = mock.work;
        queries = mock.queries;
    }

    public static void enqueue(Type jobType, List<SObject> records) { 
        enqueue(jobType, Pluck.ids(records));
    }
    public static void enqueue(Type jobType, Set<Id> recordIds) { 
        work.create(jobType, recordIds);
    }
    public static void stage(Type jobType, List<SObject> records) { }
    public static void stage(Type jobType, Set<Id> recordIds) { }
    public static void flush() {}

    public String threadId;
    public Set<Id> recordIds = new Set<Id>();
    public Set<Id> workItemIds = new Set<Id>();

    public void setWork(String threadId, Set<Id> workItemIds) {
        this.threadId = threadId;
        this.workItemIds = workItemIds;
    }

    public void enqueue() {
        System.enqueueJob(this);
    }

    public virtual void execute(Set<Id> ids) {
        throw new AsyncException('Async subclasses must override execute(Set<Id>).');
    }

    public void execute(QueueableContext context) {
        jobs.attachFinalizer(new JobWatcher(this.threadId, this.workItemIds));
        this.execute(this.getRecordIds());
    }

    Set<Id> getRecordIds() {
        List<Async__c> workItems = queries.getWorkItemsById(this.workItemIds);
        for(Async__c workItem : workItems) {
            this.recordIds.add(workItem.Record_Id__c);
        }
        return this.recordIds;
    }

    public virtual with sharing class JobService {
        public String threadId = Request.getCurrent().getRequestId();
        public boolean hasEnqueued = false;
        public virtual void enqueue() {
            if(!this.canEnqueue() || this.hasEnqueued) return;
            this.startThread();
            this.hasEnqueued = true;
        }

        public virtual void startThread() {
            System.enqueueJob(new AsyncThread(this.threadId));
        }

        public virtual void attachFinalizer(Finalizer finalizer) {
            System.attachFinalizer(finalizer);
        }

        public virtual void enqueueNextJob() {
            Async__c nextWorkItem = queries.getNextWorkItem(this.threadId);
            System.debug(nextWorkItem);
            if(nextWorkItem == null) return; //todo: this should never happen, throw an exception and alert.
            Async_Config__mdt config = queries.getJobConfig(nextWorkItem.Apex__c);
            List<Async__c> workItems = Async.queries.getMatchingWorkItems(
                this.threadId, nextWorkItem.Apex__c, Integer.valueOf(config.Batch_Size__c));
            Set<Id> workItemIds = Pluck.ids(workItems);
            
            //dynamically instantiate the async job
            Async asyncJob = (Async) Type.forName(nextWorkItem.Apex__c).newInstance();
            asyncJob.setWork(this.threadId, workItemIds);
            asyncJob.enqueue();

            work.running(workItemIds);
        }

        public virtual Boolean canEnqueue() {
            return !Test.isRunningTest();
        }
    }

    public virtual with sharing class WorkService {
        public virtual List<Id> create(Type apexClass, Set<Id> recordIds) {
            List<Async__c> workItems = new List<Async__c>();

            if (recordIds == null || recordIds.isEmpty()) return new List<Id>();
            for (Id recordId : recordIds) {
                workItems.add(new Async__c(
                    Record_Id__c = String.valueOf(recordId),
                    Status__c = 'Pending',
                    Thread__c = jobs.threadId,
                    Apex__c = String.valueOf(apexClass)
                ));
            }

            DML.insertRecords(workItems);
            return idsFrom(workItems);
        }

        public virtual void complete(Set<Id> workItemIds) {
            updateStatus(workItemIds, new Async__c(Status__c = 'Done'));
        }

        public virtual void fail(Set<Id> workItemIds, String message, String stackTrace) {
            updateStatus(workItemIds, new Async__c(
                Status__c = 'Error',
                Error_Message__c = truncate(message),
                Error_Stack_Trace__c = truncate(stackTrace)
            ));
        }

        public virtual void running(Set<Id> workItemIds) {
            updateStatus(workItemIds, new Async__c(Status__c = 'Running'));
        }

        List<Id> idsFrom(List<Async__c> workItems) {
            List<Id> ids = new List<Id>();

            for (Async__c workItem : workItems) {
                if (workItem.Id != null) {
                    ids.add(workItem.Id);
                }
            }

            return ids;
        }

        void updateStatus(Set<Id> workItemIds, Async__c values) {
            if (workItemIds == null || workItemIds.isEmpty()) {
                return;
            }

            List<SObject> updates = new List<SObject>();

            for (Id workItemId : workItemIds) {
                updates.add(new Async__c(
                    Id = workItemId,
                    Status__c = values.Status__c,
                    Error_Message__c = values.Error_Message__c,
                    Error_Stack_Trace__c = values.Error_Stack_Trace__c
                ));
            }

            DML.updateRecords(updates);
        }

        String truncate(String value) {
            if (value == null || value.length() <= 32768) {
                return value;
            }

            return value.substring(0, 32768);
        }
    }

    public virtual with sharing class QueryService {
        public virtual Async__c getNextWorkItem(String threadId) {
            System.debug(threadId);
            List<Async__c> workItems = (List<Async__c>) Query.records([
                SELECT Apex__c, Thread__c, Record_Id__c, Priority__c
                FROM Async__c
                WHERE Thread__c = :threadId 
                    AND Status__c = 'Pending'
                ORDER BY Priority__c DESC, CreatedDate ASC
                LIMIT 1
            ]);
            return workItems.isEmpty() ? null : workItems[0];
        }

        public virtual List<Async__c> getMatchingWorkItems(String threadId, String apexClass, Integer batchSize) {
            return (List<Async__c>) Query.records([
                SELECT Apex__c, Thread__c, Record_Id__c, Priority__c
                FROM Async__c
                WHERE Thread__c = :threadId 
                    AND Apex__c = :apexClass
                    AND Status__c = 'Pending'
                ORDER BY Priority__c DESC
                LIMIT :batchSize
            ]);
        }

        public virtual List<Async__c> getWorkItemsById(Set<Id> workItemIds) {
            List<Async__c> workItems = (List<Async__c>) Query.records([
                SELECT Id, Apex__c, Thread__c, Record_Id__c, Priority__c
                FROM Async__c
                WHERE Id IN :workItemIds
            ]);
            return workItems;
        }



        public virtual Async_Config__mdt getJobConfig(String apexClass) {
            List<Async_Config__mdt> configs = (List<Async_Config__mdt>) Query.records([
                SELECT Apex__c, Batch_Size__c
                FROM Async_Config__mdt
                WHERE Apex__c = :apexClass
                LIMIT 1
            ]);
            return !configs.isEmpty() ? configs[0] : new Async_Config__mdt(Batch_Size__c = 5);
        }
    }

    public with sharing class JobWatcher implements Finalizer {
        Set<Id> workItemIds;
        String threadId;
        public JobWatcher(String threadId, Set<Id> workItemIds) {
            this.workItemIds = workItemIds;
            this.threadId = threadId;
        }

        public void execute(FinalizerContext context) {
            Async.jobs.threadId = this.threadId; //set the thread context
            if (context.getResult() == ParentJobResult.SUCCESS) {
                work.complete(this.workItemIds);
                jobs.enqueueNextJob();
                return;
            }

            Exception error = context.getException();
            work.fail(
                this.workItemIds,
                error == null ? String.valueOf(context.getResult()) : error.getMessage(),
                error == null ? null : error.getStackTraceString()
            );
        }
    }

    public class AsyncException extends Exception {}
}
