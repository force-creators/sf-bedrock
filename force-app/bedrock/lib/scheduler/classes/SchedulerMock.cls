/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class SchedulerMock {
  public Scheduler.JobService jobs;
  public MetadataService metadata;
  public QueryService queries;
  String currentHash;

  public SchedulerMock() {
    jobs = new JobService();
    metadata = new MetadataService();
    queries = new QueryService();
  }

  public SchedulerMock config(Scheduler_Job__mdt config) {
    metadata.configs.add(config);
    return this;
  }

  public SchedulerMock job(Scheduler__c job) {
    if (currentHash != null && job.Hash__c == null) {
      job.Hash__c = currentHash;
    }
    queries.jobs.add(job);
    return this;
  }

  public SchedulerMock seedCurrentHash() {
    currentHash = metadata.getHash(metadata.configs);
    for (Scheduler__c job : queries.jobs) {
      job.Hash__c = currentHash;
    }
    return this;
  }

  public with sharing class JobService extends Scheduler.JobService {
    public Finalizer finalizer;
    public List<Scheduler__c> ranJobs = new List<Scheduler__c>();

    public override void run(Scheduler__c job) {
      ranJobs.add(job);
      Scheduler task = (Scheduler) Type.forName(job.Apex__c).newInstance();
      task.setSchedulerJob(job.Id).execute(null);
    }

    public override void attachFinalizer(Finalizer finalizer) {
      this.finalizer = finalizer;
    }
  }

  public with sharing class MetadataService extends Scheduler.MetadataService {
    public List<Scheduler_Job__mdt> configs = new List<Scheduler_Job__mdt>();

    public override List<Scheduler_Job__mdt> getConfigs() {
      return configs;
    }
  }

  public with sharing class QueryService extends Scheduler.QueryService {
    public List<Scheduler__c> jobs = new List<Scheduler__c>();

    public override List<Scheduler__c> getJobsByApexClasses(
      Set<String> apexClasses
    ) {
      List<Scheduler__c> rows = new List<Scheduler__c>();
      if (apexClasses == null || apexClasses.isEmpty())
        return rows;

      for (Scheduler__c job : jobs) {
        if (apexClasses.contains(job.Apex__c)) {
          rows.add(job);
        }
      }
      return rows;
    }

    public override List<Scheduler__c> getJobsByApexClassesAndMetadataHash(
      Set<String> apexClasses,
      String metadataHash
    ) {
      List<Scheduler__c> rows = new List<Scheduler__c>();
      if (apexClasses == null || apexClasses.isEmpty())
        return rows;

      for (Scheduler__c job : jobs) {
        if (apexClasses.contains(job.Apex__c) && job.Hash__c == metadataHash) {
          rows.add(job);
        }
      }
      return rows;
    }

    public override List<Scheduler__c> getJobsByMetadataHash(
      String metadataHash
    ) {
      List<Scheduler__c> rows = new List<Scheduler__c>();
      for (Scheduler__c job : jobs) {
        if (job.Hash__c == metadataHash) {
          rows.add(job);
        }
      }
      return rows;
    }

    public override List<Scheduler__c> getJobsNotInApexClasses(
      Set<String> apexClasses
    ) {
      List<Scheduler__c> rows = new List<Scheduler__c>();
      for (Scheduler__c job : jobs) {
        if (apexClasses == null || !apexClasses.contains(job.Apex__c)) {
          rows.add(job);
        }
      }
      return rows;
    }

    public override List<Scheduler__c> getEnabledJobs() {
      List<Scheduler__c> rows = new List<Scheduler__c>();
      for (Scheduler__c job : jobs) {
        if (job.Enabled__c) {
          rows.add(job);
        }
      }
      return rows;
    }
  }
}
