/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class AsyncMock {
    public WorkService work;
    public JobService jobs;
    public QueryService queries;
    public MetadataService metadata;
    public SettingsService settings;
    public ThreadMock threads;

    public AsyncMock() {
        this.work = new WorkService();
        this.jobs = new JobService();
        this.queries = new QueryService();
        this.metadata = new MetadataService();
        this.settings = new SettingsService();
        this.threads = new ThreadMock();
    }

    public AsyncMock canEnqueue() {
        this.jobs.canEnqueue = true;
        this.threads.canEnqueue();
        return this;
    }

    public AsyncMock config(Type jobType, Async_Job__mdt config) {
        this.metadata.configByApex.put(String.valueOf(jobType), config);
        return this;
    }

    public AsyncMock seedSettings(Async_Settings__c settings) {
        this.settings.setSettings(settings);
        return this;
    }

    public AsyncMock mockThreadIds() {
        this.threads.mockIds();
        return this;
    }

    public AsyncMock mockWork() {
        this.work.mockDml();
        return this;
    }

    public with sharing class WorkService extends Async.WorkService {
        public List<List<SObject>> inserts = new List<List<SObject>>();
        public List<List<SObject>> updates = new List<List<SObject>>();
        public Boolean useMockDml = false;

        public WorkService mockDml() {
            this.useMockDml = true;
            return this;
        }

        protected override void insertRecords(List<SObject> records) {
            this.inserts.add(records);
            if (!this.useMockDml) {
                super.insertRecords(records);
            }
        }

        protected override void updateRecords(List<SObject> records) {
            this.updates.add(records);
            if (!this.useMockDml) {
                super.updateRecords(records);
            }
        }
    }

    public with sharing class JobService extends Async.JobService {
        public Boolean canEnqueue = false;

        public override Boolean canEnqueue() {
            return canEnqueue;
        }

        public override void startThread(Integer failures) {
            Thread.service.start(Thread.currentId(), failures);
        }
    }

    public with sharing class QueryService extends Async.QueryService {
    }

    public with sharing class MetadataService extends Async.MetadataService {
        public Map<String, Async_Job__mdt> configByApex = new Map<String, Async_Job__mdt>();

        public override Async_Job__mdt getConfig(String apexClass) {
            if (this.configByApex.containsKey(apexClass)) {
                return this.configByApex.get(apexClass);
            }
            return super.getConfig(apexClass);
        }
    }

    public with sharing class SettingsService extends Async.SettingsService {
    }
}
