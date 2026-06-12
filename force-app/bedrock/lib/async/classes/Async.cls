public virtual with sharing class Async implements Queueable, Database.AllowsCallouts {
    public static JobService jobs = new JobService();
    public static WorkService work = new WorkService();
    public static QueryService queries = new QueryService();
    public static MetadataService metadata = new MetadataService();
    public static SettingsService settings = new SettingsService();

    @testVisible static void setMock(AsyncMock mock) {
        jobs = mock.jobs;
        work = mock.work;
        queries = mock.queries;
        metadata = mock.metadata;
        settings = mock.settings;
    }

    public static void enqueue(Type jobType, List<SObject> records) { 
        enqueue(jobType, Pluck.ids(records));
    }
    public static void enqueue(Type jobType, Set<Id> recordIds) { 
        work.create(jobType, recordIds);
    }
    public static void stage(Type jobType, List<SObject> records) {
        stage(jobType, Pluck.ids(records));
    }
    public static void stage(Type jobType, Set<Id> recordIds) {
        work.stage(jobType, recordIds);
    }
    public static void flush() {
        work.flush();
    }

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
        JobWatcher watcher = jobs.watch(this.threadId, this.workItemIds);
        jobs.attachFinalizer(watcher);

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
        @testVisible JobWatcher watcher;
        @testVisible Boolean isFinalizer = false;

        public virtual void enqueue() {
            if(!this.canEnqueue() || this.hasEnqueued || System.isQueueable() || this.isFinalizer || this.isRunningThread()) return;
            this.startThread();
            this.hasEnqueued = true;
        }

        public virtual JobWatcher watch(String threadId, Set<Id> workItemIds) {
            this.watcher = new JobWatcher(threadId, workItemIds);
            return this.watcher;
        }

        public virtual Boolean isRunningThread() {
            return this.threadId != Request.getCurrent().getRequestId();
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
            work.running(workItemIds);
            asyncJob.enqueue();
        }

        public void retry(Set<Id> workItemIds) {
            work.retry(workItemIds);
        }

        public virtual void handleFailure(Set<Id> workItemIds, String message, String stackTrace) {
            List<Async__c> toRetry = new List<Async__c>();
            Set<Id> toFail = new Set<Id>();

            for (Async__c workItem : queries.getWorkItemsById(workItemIds)) {
                if (this.shouldAutoRetry(workItem)) {
                    toRetry.add(workItem);
                } else {
                    toFail.add(workItem.Id);
                }
            }

            work.fail(toFail, message, stackTrace);
            work.autoRetry(toRetry);
        }

        public virtual Boolean shouldAutoRetry(Async__c workItem) {
            Decimal maxRetries = Async.metadata.getConfig(workItem.Apex__c).Max_Retries__c;
            if (maxRetries == null || maxRetries <= 0) return false;

            Decimal retryCount = workItem.Retry_Count__c == null ? 0 : workItem.Retry_Count__c;
            return retryCount < maxRetries;
        }

        public virtual Boolean canEnqueue() {
            return !Test.isRunningTest();
        }
    }

    public virtual with sharing class WorkService {
        @testVisible Map<String, Set<Id>> buffer = new Map<String, Set<Id>>();

        public virtual void stage(Type apexClass, Set<Id> recordIds) {
            addWork(this.buffer, String.valueOf(apexClass), recordIds);
        }

        public virtual void flush() {
            if (this.buffer.isEmpty()) return;

            Map<String, Set<Id>> workToCreate = new Map<String, Set<Id>>(this.buffer);

            if (this.shouldDefer()) {
                this.defer(workToCreate);
                this.buffer.clear();
                return;
            }

            this.create(workToCreate);
            this.buffer.clear();
        }

        public virtual List<Id> create(Type apexClass, Set<Id> recordIds) {
            return create(String.valueOf(apexClass), recordIds);
        }

        public virtual List<Id> create(String apexClass, Set<Id> recordIds) {
            Map<String, Set<Id>> workByApex = new Map<String, Set<Id>>();
            workByApex.put(apexClass, recordIds);
            return create(workByApex);
        }

        public virtual List<Id> create(Map<String, Set<Id>> workByApex) {
            if (this.shouldDefer()) {
                this.defer(workByApex);
                return new List<Id>();
            }

            return insertWork(workByApex);
        }

        List<Id> insertWork(Map<String, Set<Id>> workByApex) {
            List<Async__c> workItems = new List<Async__c>();

            if (workByApex == null || workByApex.isEmpty()) return new List<Id>();
            for (String apexClass : workByApex.keySet()) {
                workItems.addAll(newWorkItems(apexClass, workByApex.get(apexClass)));
            }

            if (workItems.isEmpty()) return new List<Id>();
            DML.insertRecords(workItems);
            return idsFrom(workItems);
        }

        List<Async__c> newWorkItems(String apexClass, Set<Id> recordIds) {
            List<Async__c> workItems = new List<Async__c>();
            Decimal priority = this.getPriority(apexClass);

            if (String.isBlank(apexClass) || recordIds == null || recordIds.isEmpty()) return workItems;
            for (Id recordId : recordIds) {
                workItems.add(new Async__c(
                    Record_Id__c = String.valueOf(recordId),
                    Status__c = 'Pending',
                    Thread__c = jobs.threadId,
                    Apex__c = apexClass,
                    Priority__c = priority
                ));
            }

            return workItems;
        }

        Decimal getPriority(String apexClass) {
            Decimal priority = Async.metadata.getConfig(apexClass).Priority__c;
            return priority == null ? 0 : priority;
        }

        Boolean shouldDefer() {
            return jobs.watcher != null;
        }

        void defer(Map<String, Set<Id>> workByApex) {
            if (workByApex == null || workByApex.isEmpty()) return;

            for (String apexClass : workByApex.keySet()) {
                this.defer(apexClass, workByApex.get(apexClass));
            }
        }

        void defer(String apexClass, Set<Id> recordIds) {
            if (!this.shouldDefer()) return;
            addWork(jobs.watcher.deferredWork, apexClass, recordIds);
        }

        void addWork(Map<String, Set<Id>> workByApex, String apexClass, Set<Id> recordIds) {
            if (String.isBlank(apexClass) || recordIds == null || recordIds.isEmpty()) return;

            if (!workByApex.containsKey(apexClass)) {
                workByApex.put(apexClass, new Set<Id>());
            }
            workByApex.get(apexClass).addAll(recordIds);
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

        public virtual void retry(Set<Id> workItemIds) {
            System.debug('Current Thread: ' + jobs.threadId);
            System.debug('TX: Id:' + Request.getCurrent().getRequestId());
            updateStatus(workItemIds, new Async__c(Status__c = 'Pending', Thread__c = jobs.threadId));
        }

        public virtual void autoRetry(List<Async__c> workItems) {
            if (workItems == null || workItems.isEmpty()) return;

            List<SObject> updates = new List<SObject>();
            for (Async__c workItem : workItems) {
                Decimal retryCount = workItem.Retry_Count__c == null ? 0 : workItem.Retry_Count__c;
                updates.add(new Async__c(
                    Id = workItem.Id,
                    Status__c = 'Pending',
                    Thread__c = jobs.threadId,
                    Retry_Count__c = retryCount + 1
                ));
            }

            DML.updateRecords(updates);
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
                Async__c updateRecord = new Async__c(Id = workItemId);
                if(values.Status__c != null) updateRecord.Status__c = values.Status__c;
                if(values.Error_Message__c != null) updateRecord.Error_Message__c = values.Error_Message__c;
                if(values.Error_Stack_Trace__c != null) updateRecord.Error_Stack_Trace__c = values.Error_Stack_Trace__c;
                if(values.Thread__c != null) updateRecord.Thread__c = values.Thread__c;
                updates.add(updateRecord);
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
                SELECT Id, Apex__c, Thread__c, Record_Id__c, Priority__c, Retry_Count__c
                FROM Async__c
                WHERE Id IN :workItemIds
            ]);
            return workItems;
        }

        public virtual Async_Config__mdt getJobConfig(String apexClass) {
            return Async.metadata.getConfig(apexClass);
        }
    }

    public virtual with sharing class MetadataService {
        @testVisible Map<String, Async_Config__mdt> configByApex = new Map<String, Async_Config__mdt>();

        public virtual Async_Config__mdt getConfig(String apexClass) {
            if (!this.configByApex.containsKey(apexClass)) {
                this.configByApex.put(apexClass, this.loadConfig(apexClass));
            }
            return this.configByApex.get(apexClass);
        }

        protected virtual Async_Config__mdt loadConfig(String apexClass) {
            List<Async_Config__mdt> configs = (List<Async_Config__mdt>) Query.records([
                SELECT Apex__c, Batch_Size__c, Max_Retries__c, Priority__c
                FROM Async_Config__mdt
                WHERE Apex__c = :apexClass
                LIMIT 1
            ]);
            return !configs.isEmpty() ? configs[0] : new Async_Config__mdt(Batch_Size__c = 5, Priority__c = 0);
        }
    }

    public virtual with sharing class SettingsService {
        @testVisible Async_Settings__c values;

        public virtual Async_Settings__c getSettings() {
            if (this.values == null) {
                this.values = this.loadSettings();
            }
            return this.values;
        }

        public virtual void setSettings(Async_Settings__c values) {
            this.values = values;
        }

        protected virtual Async_Settings__c loadSettings() {
            Async_Settings__c settings = Async_Settings__c.getInstance();
            return settings == null ? new Async_Settings__c() : settings;
        }
    }

    public with sharing class JobWatcher implements Finalizer {
        Set<Id> workItemIds;
        String threadId;
        Map<String, Set<Id>> deferredWork = new Map<String, Set<Id>>();

        public JobWatcher(String threadId, Set<Id> workItemIds) {
            this.workItemIds = workItemIds;
            this.threadId = threadId;
        }

        public void execute(FinalizerContext context) {
            Async.jobs.threadId = this.threadId; //set the thread context
            Async.jobs.isFinalizer = true;
            try {
                if (context.getResult() == ParentJobResult.SUCCESS) {
                    work.complete(this.workItemIds);
                    this.createDeferredWork();
                    jobs.enqueueNextJob();
                    return;
                }

                Exception error = context.getException();
                jobs.handleFailure(
                    this.workItemIds,
                    error == null ? String.valueOf(context.getResult()) : error.getMessage(),
                    error == null ? null : error.getStackTraceString()
                );
                jobs.enqueueNextJob();
            } finally {
                Async.jobs.isFinalizer = false;
            }
        }

        void createDeferredWork() {
            if (this.deferredWork.isEmpty()) return;
            work.insertWork(this.deferredWork);
        }
    }

    public class AsyncException extends Exception {}
}
