/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual inherited sharing class Limiter {
  static Service instance = new Service();

  @testVisible
  static void setMock(Service mock) {
    instance = mock == null ? new Service() : mock;
  }

  public static Map<String, LimitUsage> getLimits() {
    return instance.getLimits();
  }

  public static LimitUsage getLimit(String name) {
    return instance.getLimit(name);
  }

  public static LimitUsage getLimit(types name) {
    return instance.getLimit(name);
  }

  public static Boolean isSafe(String name) {
    return instance.isSafe(name);
  }

  public static Boolean isSafe(String name, Decimal thresholdPercent) {
    return instance.isSafe(name, thresholdPercent);
  }

  public static Boolean isSafe(types name) {
    return instance.isSafe(name);
  }

  public static Boolean isSafe(types name, Decimal thresholdPercent) {
    return instance.isSafe(name, thresholdPercent);
  }

  public static String key(types name) {
    if (name == types.QUEUEABLE_JOBS)
      return 'QueueableJobs';
    if (name == types.SOQL_QUERIES)
      return 'SOQLQueries';
    if (name == types.CPU_TIME)
      return 'CPUTime';
    if (name == types.HEAP_SIZE)
      return 'HeapSize';
    if (name == types.DML_STATEMENTS)
      return 'DMLStatements';
    if (name == types.DAILY_ASYNC_APEX_EXECUTIONS)
      return 'DailyAsyncApexExecutions';
    if (name == types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS)
      return 'DailyStandardVolumePlatformEvents';
    return null;
  }

  public virtual inherited sharing class Service {
    public virtual Map<String, LimitUsage> getLimits() {
      Map<String, LimitUsage> results = new Map<String, LimitUsage>();

      this.add(
        results,
        new LimitUsage(
          Limiter.key(types.QUEUEABLE_JOBS),
          Limits.getQueueableJobs(),
          Limits.getLimitQueueableJobs()
        )
      );
      this.add(
        results,
        new LimitUsage(
          Limiter.key(types.SOQL_QUERIES),
          Limits.getQueries(),
          Limits.getLimitQueries()
        )
      );
      this.add(
        results,
        new LimitUsage(
          Limiter.key(types.CPU_TIME),
          Limits.getCpuTime(),
          Limits.getLimitCpuTime()
        )
      );
      this.add(
        results,
        new LimitUsage(
          Limiter.key(types.HEAP_SIZE),
          Limits.getHeapSize(),
          Limits.getLimitHeapSize()
        )
      );
      this.add(
        results,
        new LimitUsage(
          Limiter.key(types.DML_STATEMENTS),
          Limits.getDmlStatements(),
          Limits.getLimitDmlStatements()
        )
      );

      for (System.OrgLimit orgLimit : OrgLimits.getMap().values()) {
        this.add(
          results,
          new LimitUsage(
            orgLimit.getName(),
            orgLimit.getValue(),
            orgLimit.getLimit()
          )
        );
      }

      return results;
    }

    public virtual LimitUsage getLimit(String name) {
      return this.getLimits().get(name);
    }

    public virtual LimitUsage getLimit(types name) {
      return this.getLimit(Limiter.key(name));
    }

    public virtual Boolean isSafe(String name) {
      return this.isSafe(name, 90);
    }

    public virtual Boolean isSafe(String name, Decimal thresholdPercent) {
      LimitUsage limitUsage = this.getLimit(name);
      if (limitUsage == null) {
        return false;
      }

      Decimal threshold = thresholdPercent == null ? 90 : thresholdPercent;
      return limitUsage.ratio < (threshold / 100);
    }

    public virtual Boolean isSafe(types name) {
      return this.isSafe(name, 90);
    }

    public virtual Boolean isSafe(types name, Decimal thresholdPercent) {
      return this.isSafe(Limiter.key(name), thresholdPercent);
    }

    void add(Map<String, LimitUsage> results, LimitUsage limitUsage) {
      results.put(limitUsage.name, limitUsage);
    }
  }

  public inherited sharing class LimitUsage {
    public String name;
    public Integer used;
    public Integer allowed;
    public Integer remaining;
    public Decimal ratio;

    public LimitUsage(String name, Integer used, Integer allowed) {
      this.name = name;
      this.used = used == null ? 0 : used;
      this.allowed = allowed == null ? 0 : allowed;
      this.remaining = Math.max(this.allowed - this.used, 0);
      this.ratio = this.allowed <= 0
        ? 0
        : (Decimal.valueOf(this.used) / Decimal.valueOf(this.allowed))
            .setScale(6);
    }
  }

  public enum types {
    QUEUEABLE_JOBS,
    SOQL_QUERIES,
    CPU_TIME,
    HEAP_SIZE,
    DML_STATEMENTS,
    DAILY_ASYNC_APEX_EXECUTIONS,
    DAILY_STANDARD_VOLUME_PLATFORM_EVENTS
  }
}
