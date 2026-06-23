/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class ThreadMonitorController {
  static final Integer MAX_ROWS = 500;
  static final Set<String> SORT_FIELDS = new Set<String>{
    'threadNumber',
    'pool',
    'threadKey',
    'status',
    'startedAt',
    'heartbeatAt',
    'completedAt',
    'createdDate'
  };

  @AuraEnabled
  public static List<ThreadRow> getRunning(
    String searchTerm,
    String sortBy,
    String sortDirection
  ) {
    return getRows('running', searchTerm, sortBy, sortDirection);
  }

  @AuraEnabled
  public static List<ThreadRow> getCompleted(
    String searchTerm,
    String sortBy,
    String sortDirection
  ) {
    return getRows('completed', searchTerm, sortBy, sortDirection);
  }

  static List<ThreadRow> getRows(
    String view,
    String searchTerm,
    String sortBy,
    String sortDirection
  ) {
    String normalizedSearchTerm = BedrockConsoleSupport.normalizeSearchTerm(
      searchTerm
    );
    String orderByField = sortField(sortBy);
    String orderByDirection = BedrockConsoleSupport.sortOrder(sortDirection);
    Datetime staleBefore = System.now()
      .addMinutes(-Thread.settings.recoveryThresholdMinutes());
    String doneStatus = Thread.consts.DONE;
    String whereClause = view == 'completed'
      ? 'Status__c = :doneStatus'
      : 'Status__c != :doneStatus';
    String orderClause = view == 'completed'
      ? 'Completed__c DESC NULLS LAST, CreatedDate DESC'
      : 'Status__c DESC, Heartbeat__c ASC NULLS LAST';

    List<Thread__c> threads = Database.query(
      'SELECT Id, Name, Pool__c, Thread_Key__c, Status__c, Run_Key__c, ' +
        'Started__c, Heartbeat__c, Completed__c, CreatedBy.Name, CreatedDate ' +
        'FROM Thread__c ' +
        'WHERE ' +
        whereClause +
        ' ' +
        'ORDER BY ' +
        orderClause +
        ' ' +
        'LIMIT ' +
        MAX_ROWS
    );

    List<ThreadRow> rows = new List<ThreadRow>();
    for (Thread__c threadRecord : threads) {
      ThreadRow row = new ThreadRow(threadRecord, staleBefore);
      if (matchesFilter(row, normalizedSearchTerm)) {
        rows.add(row);
      }
    }

    rows.sort(new ThreadRowSorter(orderByField, orderByDirection));
    return rows;
  }

  static String sortField(String sortBy) {
    if (!SORT_FIELDS.contains(sortBy)) {
      return 'createdDate';
    }

    Map<String, String> fieldByName = new Map<String, String>{
      'threadNumber' => 'threadNumber',
      'pool' => 'pool',
      'threadKey' => 'threadKey',
      'status' => 'status',
      'startedAt' => 'startedAt',
      'heartbeatAt' => 'heartbeatAt',
      'completedAt' => 'completedAt',
      'createdDate' => 'createdDate'
    };
    return fieldByName.get(sortBy);
  }

  static Boolean matchesFilter(ThreadRow row, String searchTerm) {
    if (searchTerm == null) {
      return true;
    }

    return BedrockConsoleSupport.containsIgnoreCase(
        row.threadNumber,
        searchTerm
      ) ||
      BedrockConsoleSupport.containsIgnoreCase(row.pool, searchTerm) ||
      BedrockConsoleSupport.containsIgnoreCase(row.threadKey, searchTerm) ||
      BedrockConsoleSupport.containsIgnoreCase(row.status, searchTerm) ||
      BedrockConsoleSupport.containsIgnoreCase(row.createdBy, searchTerm) ||
      BedrockConsoleSupport.containsIgnoreCase(row.runKey, searchTerm);
  }

  static String runKeyPreview(String runKey) {
    if (String.isBlank(runKey))
      return null;
    if (runKey.length() <= 12)
      return runKey;
    return runKey.left(8) + '...' + runKey.right(4);
  }

  static String health(Thread__c threadRecord, Boolean isStale) {
    if (threadRecord.Status__c == Thread.consts.DONE)
      return 'Completed';
    if (isStale)
      return 'Stale heartbeat';
    if (threadRecord.Status__c == Thread.consts.PENDING)
      return 'Waiting';
    return 'Running';
  }

  public class ThreadRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String threadNumber;
    @AuraEnabled
    public String pool;
    @AuraEnabled
    public String threadKey;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String health;
    @AuraEnabled
    public Boolean isStale;
    @AuraEnabled
    public String runKey;
    @AuraEnabled
    public Datetime startedAt;
    @AuraEnabled
    public Datetime heartbeatAt;
    @AuraEnabled
    public Datetime completedAt;
    @AuraEnabled
    public String createdBy;
    @AuraEnabled
    public Datetime createdDate;

    ThreadRow(Thread__c threadRecord, Datetime staleBefore) {
      this.id = threadRecord.Id;
      this.threadNumber = threadRecord.Name;
      this.pool = String.isBlank(threadRecord.Pool__c)
        ? Thread.consts.ASYNC_POOL
        : threadRecord.Pool__c;
      this.threadKey = threadRecord.Thread_Key__c;
      this.status = threadRecord.Status__c;
      this.isStale =
        threadRecord.Status__c != Thread.consts.DONE &&
        threadRecord.Heartbeat__c != null &&
        threadRecord.Heartbeat__c < staleBefore;
      this.health = ThreadMonitorController.health(threadRecord, this.isStale);
      this.runKey = runKeyPreview(threadRecord.Run_Key__c);
      this.startedAt = threadRecord.Started__c;
      this.heartbeatAt = threadRecord.Heartbeat__c;
      this.completedAt = threadRecord.Completed__c;
      this.createdBy = threadRecord.CreatedBy.Name;
      this.createdDate = threadRecord.CreatedDate;
    }
  }

  class ThreadRowSorter implements Comparator<ThreadRow> {
    String sortBy;
    String sortDirection;

    ThreadRowSorter(String sortBy, String sortDirection) {
      this.sortBy = sortBy;
      this.sortDirection = sortDirection;
    }

    public Integer compare(ThreadRow left, ThreadRow right) {
      Integer result;

      result = BedrockConsoleSupport.compareValues(
        valueOf(left, this.sortBy),
        valueOf(right, this.sortBy)
      );

      return this.sortDirection == 'ASC' ? result : -result;
    }

    Object valueOf(ThreadRow row, String fieldName) {
      if (fieldName == 'pool')
        return row.pool;
      if (fieldName == 'threadKey')
        return row.threadKey;
      if (fieldName == 'status')
        return row.status;
      if (fieldName == 'startedAt')
        return row.startedAt;
      if (fieldName == 'heartbeatAt')
        return row.heartbeatAt;
      if (fieldName == 'completedAt')
        return row.completedAt;
      if (fieldName == 'createdDate')
        return row.createdDate;
      return row.threadNumber;
    }
  }
}
