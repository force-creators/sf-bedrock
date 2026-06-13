public with sharing class AsyncMock {
    
    public WorkService work;
    public JobService jobs;
    public QueryService queries;
    public MetadataService metadata;
    public SettingsService settings;

    public AsyncMock() {
        this.work = new WorkService();
        this.jobs = new JobService();
        this.queries = new QueryService();
        this.metadata = new MetadataService();
        this.settings = new SettingsService();
    }

    public AsyncMock canEnqueue() {
        this.jobs.canEnqueue = true;
        return this;
    }

    public AsyncMock config(Type jobType, Async_Config__mdt config) {
        this.metadata.configByApex.put(String.valueOf(jobType), config);
        return this;
    }

    public AsyncMock seedSettings(Async_Settings__c settings) {
        this.settings.setSettings(settings);
        return this;
    }


    public with sharing class WorkService extends Async.WorkService{

    }

    public with sharing class JobService extends Async.JobService {
        public Boolean canEnqueue = false;

        public override Boolean canEnqueue() {
            return canEnqueue;
        }

        public override void startThread(Integer failureCount) {
            AsyncOptions options = new AsyncOptions();
            options.maximumQueueableStackDepth = 5;
            System.enqueueJob(new AsyncThread(this.threadId, failureCount), options);
        }

    }

    public with sharing class QueryService extends Async.QueryService {
    }

    public with sharing class MetadataService extends Async.MetadataService {
        public Map<String, Async_Config__mdt> configByApex = new Map<String, Async_Config__mdt>();

        public override Async_Config__mdt getConfig(String apexClass) {
            if (this.configByApex.containsKey(apexClass)) {
                return this.configByApex.get(apexClass);
            }
            return super.getConfig(apexClass);
        }
    }

    public with sharing class SettingsService extends Async.SettingsService {
    }
}
