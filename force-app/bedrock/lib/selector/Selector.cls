/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public virtual inherited sharing class Selector {
  @testvisible
  static Map<String, Selector> instancesByKey = new Map<String, Selector>();

  protected String sObjectName;
  protected Set<String> fields = new Set<String>();
  protected Set<String> whereClauses = new Set<String>();

  public Selector(String sObjectName, Set<String> fields) {
    this(sObjectName, fields, new Set<String>());
  }

  public Selector(
    String sObjectName,
    Set<String> fields,
    Set<String> whereClauses
  ) {
    if (String.isBlank(sObjectName)) {
      throw new SelectorException('Selector requires an SObject name.');
    }
    if (fields == null || fields.isEmpty()) {
      throw new SelectorException('Selector requires at least one field.');
    }

    this.sObjectName = sObjectName;
    this.fields.addAll(fields);
    this.fields.add('Id');

    if (whereClauses != null) {
      for (String whereClause : whereClauses) {
        if (!String.isBlank(whereClause)) {
          this.whereClauses.add(whereClause);
        }
      }
    }
  }

  public static Selector instance(Selector selector) {
    String key = selector.key();
    if (!instancesByKey.containsKey(key)) {
      instancesByKey.put(key, selector);
    }
    return instancesByKey.get(key);
  }

  @testvisible
  static void clearInstances() {
    instancesByKey.clear();
  }

  public virtual List<SObject> records(Set<Id> ids) {
    if (ids == null || ids.isEmpty()) {
      return new List<SObject>();
    }
    return this.query(ids);
  }

  public virtual SObject record(Id id) {
    List<SObject> records = this.records(new Set<Id>{ id });
    if (records.isEmpty()) {
      return null;
    }
    return records[0];
  }

  public virtual Map<Id, SObject> recordsById(Set<Id> ids) {
    Map<Id, SObject> recordsById = new Map<Id, SObject>();
    for (SObject record : this.records(ids)) {
      recordsById.put(record.Id, record);
    }
    return recordsById;
  }

  public virtual List<SObject> query(Set<Id> ids) {
    return Query.records(Database.query(this.queryText(ids)));
  }

  public virtual String key() {
    return this.className() + ':' + String.valueOf(this.contractHashCode());
  }

  public virtual String cacheKey(Id id) {
    return this.key() + ':' + String.valueOf(id);
  }

  public virtual Integer contractHashCode() {
    return this.contract().hashCode();
  }

  public virtual Set<String> contract() {
    Set<String> contract = new Set<String>{ 'FROM:' + this.sObjectName };
    for (String field : this.fields) {
      contract.add('SELECT:' + field);
    }
    for (String whereClause : this.whereClauses) {
      contract.add('WHERE:' + whereClause);
    }
    return contract;
  }

  public virtual String className() {
    return String.valueOf(this).substringBefore(':');
  }

  @testvisible
  String queryText(Set<Id> ids) {
    List<String> selectedFields = this.sorted(this.fields);
    List<String> clauses = new List<String>{ 'Id IN :ids' };

    for (String whereClause : this.sorted(this.whereClauses)) {
      clauses.add('(' + whereClause + ')');
    }

    return 'SELECT ' +
      String.join(selectedFields, ', ') +
      ' FROM ' +
      this.sObjectName +
      ' WHERE ' +
      String.join(clauses, ' AND ');
  }

  protected List<String> sorted(Set<String> values) {
    List<String> result = new List<String>();
    if (values != null) {
      result.addAll(values);
    }
    result.sort();
    return result;
  }

  protected Set<Id> missingIds(Set<Id> ids, Map<Id, SObject> recordsById) {
    Set<Id> missingIds = new Set<Id>();
    if (ids == null) {
      return missingIds;
    }

    for (Id id : ids) {
      if (id != null && !recordsById.containsKey(id)) {
        missingIds.add(id);
      }
    }
    return missingIds;
  }

  protected void store(List<SObject> records, Map<Id, SObject> recordsById) {
    for (SObject record : records) {
      recordsById.put(record.Id, record);
    }
  }

  protected List<SObject> ordered(Set<Id> ids, Map<Id, SObject> recordsById) {
    List<SObject> result = new List<SObject>();
    if (ids == null) {
      return result;
    }

    for (Id id : ids) {
      SObject record = recordsById.get(id);
      if (record != null) {
        result.add(record);
      }
    }
    return result;
  }

  public virtual inherited sharing class Once extends Selector {
    protected Map<Id, SObject> loadedRecordsById = new Map<Id, SObject>();

    public Once(String sObjectName, Set<String> fields) {
      super(sObjectName, fields);
    }

    public Once(
      String sObjectName,
      Set<String> fields,
      Set<String> whereClauses
    ) {
      super(sObjectName, fields, whereClauses);
    }

    public override virtual List<SObject> records(Set<Id> ids) {
      Set<Id> missingIds = this.missingIds(ids, this.loadedRecordsById);
      if (!missingIds.isEmpty()) {
        this.store(this.query(missingIds), this.loadedRecordsById);
      }
      return this.ordered(ids, this.loadedRecordsById);
    }
  }

  public virtual inherited sharing class Cached extends Once {
    protected PlatformCache cache;

    public Cached(String sObjectName, Set<String> fields, PlatformCache cache) {
      this(sObjectName, fields, new Set<String>(), cache);
    }

    public Cached(
      String sObjectName,
      Set<String> fields,
      String partitionName
    ) {
      this(
        sObjectName,
        fields,
        new Set<String>(),
        new PlatformCache.Org(partitionName)
      );
    }

    public Cached(
      String sObjectName,
      Set<String> fields,
      Set<String> whereClauses,
      PlatformCache cache
    ) {
      super(sObjectName, fields, whereClauses);
      if (cache == null) {
        throw new SelectorException(
          'Selector.Cached requires a cache adapter.'
        );
      }
      this.cache = cache;
    }

    public Cached(
      String sObjectName,
      Set<String> fields,
      Set<String> whereClauses,
      String partitionName
    ) {
      this(
        sObjectName,
        fields,
        whereClauses,
        new PlatformCache.Org(partitionName)
      );
    }

    public override List<SObject> records(Set<Id> ids) {
      Set<Id> missingIds = this.missingIds(ids, this.loadedRecordsById);

      for (Id id : missingIds.clone()) {
        Object cachedRecord = this.cache.get(this.cacheKey(id));
        if (cachedRecord instanceof SObject) {
          this.loadedRecordsById.put(id, (SObject) cachedRecord);
          missingIds.remove(id);
        }
      }

      if (!missingIds.isEmpty()) {
        List<SObject> queriedRecords = this.query(missingIds);
        this.store(queriedRecords, this.loadedRecordsById);
        for (SObject record : queriedRecords) {
          this.cache.put(this.cacheKey(record.Id), record);
        }
      }

      return this.ordered(ids, this.loadedRecordsById);
    }
  }

  public class SelectorException extends Exception {
  }
}
