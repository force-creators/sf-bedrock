/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual with sharing class ThreadRunner implements Queueable {
  public Id threadId;
  public Integer failures;
  public String runKey;

  public static Service service = new Service();

  public ThreadRunner(Id threadId, Integer failures) {
    this(threadId, failures, null);
  }

  public ThreadRunner(Id threadId, Integer failures, String runKey) {
    this.threadId = threadId;
    this.failures = failures == null ? 0 : failures;
    this.runKey = String.isBlank(runKey)
      ? Thread.service.currentRunKey(threadId)
      : runKey;
  }

  @testVisible
  public static void setMock(Service mock) {
    service = mock;
  }

  @testVisible
  public static void reset() {
    service = new Service();
  }

  public void execute(QueueableContext context) {
    Thread.setCurrent(this.threadId);
    if (!service.isRunAuthorized(this.threadId, this.runKey))
      return;

    Thread.service.heartbeat(this.threadId);
    service.dispatch(this.threadId, this.failures, this.runKey);
  }

  public virtual with sharing class Service {
    @testVisible
    Map<String, Dispatcher> dispatchers = new Map<String, Dispatcher>();

    public virtual void register(String pool, Dispatcher dispatcher) {
      if (String.isBlank(pool) || dispatcher == null)
        return;
      this.dispatchers.put(pool, dispatcher);
    }

    public virtual void start(Id threadId, Integer failures) {
      if (threadId == null)
        return;

      start(threadId, failures, Thread.service.startRun(threadId));
    }

    public virtual void start(Id threadId, Integer failures, String runKey) {
      if (threadId == null || String.isBlank(runKey))
        return;
      if (!Thread.service.canStartQueueableWork()) {
        Thread.pause(threadId, Thread.service.queueablePauseReason(), runKey);
        return;
      }

      System.enqueueJob(new ThreadRunner(threadId, failures, runKey));
    }

    public virtual void dispatch(Id threadId, Integer failures) {
      dispatch(threadId, failures, Thread.service.currentRunKey(threadId));
    }

    public virtual void dispatch(Id threadId, Integer failures, String runKey) {
      dispatcherForWork(threadId).dispatch(threadId, failures, runKey);
    }

    public virtual Boolean hasPendingWork(Id threadId) {
      return dispatcherForWork(threadId).hasPendingWork(threadId);
    }

    public virtual Id claimNextAfterDrain(String pool) {
      String normalizedPool = normalizePool(pool);
      Id nextThreadId = Thread.service.claimNext(normalizedPool);
      if (nextThreadId != null)
        return nextThreadId;

      String fallbackPool = fallbackPoolAfterDrain(normalizedPool);
      return String.isBlank(fallbackPool)
        ? null
        : Thread.service.claimNext(fallbackPool);
    }

    public virtual String fallbackPoolAfterDrain(String pool) {
      return dispatcherForPool(pool).fallbackPoolAfterDrain();
    }

    public virtual Boolean isUserScoped(String pool) {
      String normalizedPool = normalizePool(pool);
      if (this.dispatchers.containsKey(normalizedPool)) {
        return this.dispatchers.get(normalizedPool).isUserScoped();
      }
      if (
        normalizedPool == EventRelay.consts.PUBLISH_POOL ||
        normalizedPool == EventRelay.consts.PROCESS_POOL
      ) {
        return false;
      }
      return true;
    }

    public virtual Integer maxThreads(String pool) {
      return Thread.settings.maxThreads();
    }

    public virtual Boolean isRunAuthorized(Id threadId, String runKey) {
      return Thread.service.isRunAuthorized(threadId, runKey);
    }

    public virtual Dispatcher dispatcherFor(Id threadId) {
      Thread__c threadRecord = Thread.queries.getThread(threadId);
      String pool = threadRecord == null || String.isBlank(threadRecord.Pool__c)
        ? Thread.consts.ASYNC_POOL
        : threadRecord.Pool__c;
      return dispatcherForPool(pool);
    }

    public virtual Dispatcher dispatcherForWork(Id threadId) {
      Thread__c threadRecord = Thread.queries.getThread(threadId);
      String pool = threadRecord == null || String.isBlank(threadRecord.Pool__c)
        ? Thread.consts.ASYNC_POOL
        : normalizePool(threadRecord.Pool__c);
      Dispatcher poolDispatcher = dispatcherForPool(pool);
      String fallbackPool = poolDispatcher.fallbackPoolAfterDrain();
      if (
        String.isBlank(fallbackPool) || poolDispatcher.hasPendingWork(threadId)
      ) {
        return poolDispatcher;
      }

      Dispatcher fallbackDispatcher = dispatcherForPool(fallbackPool);
      return fallbackDispatcher.hasPendingWork(threadId)
        ? fallbackDispatcher
        : poolDispatcher;
    }

    public virtual Dispatcher dispatcherForPool(String pool) {
      String normalizedPool = normalizePool(pool);
      if (this.dispatchers.containsKey(normalizedPool)) {
        return this.dispatchers.get(normalizedPool);
      }
      if (normalizedPool == Thread.consts.ASYNC_POOL) {
        return new Async.ThreadDispatcher();
      }
      if (normalizedPool == EventRelay.consts.PUBLISH_POOL) {
        return new EventRelay.ThreadDispatcher();
      }
      if (normalizedPool == EventRelay.consts.PROCESS_POOL) {
        return new EventRelay.ProcessThreadDispatcher();
      }
      throw new ThreadRunnerException(
        'No ThreadRunner dispatcher is registered for pool ' +
          normalizedPool +
          '.'
      );
    }

    String normalizePool(String pool) {
      return String.isBlank(pool) ? Thread.consts.ASYNC_POOL : pool.trim();
    }
  }

  public virtual with sharing class Dispatcher {
    public virtual void dispatch(Id threadId, Integer failures) {
      throw new ThreadRunnerException(
        'ThreadRunner dispatchers must implement dispatch(Id, Integer).'
      );
    }

    public virtual void dispatch(Id threadId, Integer failures, String runKey) {
      dispatch(threadId, failures);
    }

    public virtual Boolean hasPendingWork(Id threadId) {
      return false;
    }

    public virtual Boolean hasRecoverableWork(Id threadId) {
      return hasPendingWork(threadId);
    }

    public virtual void prepareRecovery(Id threadId) {
    }

    public virtual Integer maxThreads() {
      return 1;
    }

    public virtual Boolean isUserScoped() {
      return true;
    }

    public virtual String fallbackPoolAfterDrain() {
      return null;
    }
  }

  public class ThreadRunnerException extends Exception {
  }
}
