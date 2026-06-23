/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public abstract inherited sharing class PlatformCache {
  public static PartitionRegistry partition = new PartitionRegistry();
  public static final Constants consts = new Constants();

  @testvisible
  static void setMock(PlatformCache.Partition partitionMock) {
    partition.setMock(partitionMock);
  }

  @testvisible
  static void setOrgMock(PlatformCache.Partition partitionMock) {
    partition.setOrgMock(partitionMock);
  }

  @testvisible
  static void setSessionMock(PlatformCache.Partition partitionMock) {
    partition.setSessionMock(partitionMock);
  }

  public abstract Object get(String key);
  public abstract void put(String key, Object value);
  public abstract void remove(String key);

  public virtual inherited sharing class Partition extends PlatformCache {
    public String partitionName;
    String scope;

    public Partition(String partitionName) {
      this(partitionName, PlatformCache.consts.ORG_SCOPE);
    }

    public Partition(String partitionName, String scope) {
      this.partitionName = partitionName;
      this.scope = scope;
    }

    public override virtual Object get(String key) {
      if (this.scope == PlatformCache.consts.SESSION_SCOPE)
        return Cache.Session.getPartition(this.partitionName).get(key);
      return Cache.Org.getPartition(this.partitionName).get(key);
    }

    public override virtual void put(String key, Object value) {
      if (this.scope == PlatformCache.consts.SESSION_SCOPE) {
        Cache.Session.getPartition(this.partitionName).put(key, value);
        return;
      }
      Cache.Org.getPartition(this.partitionName).put(key, value);
    }

    public override virtual void remove(String key) {
      if (this.scope == PlatformCache.consts.SESSION_SCOPE) {
        Cache.Session.getPartition(this.partitionName).remove(key);
        return;
      }
      Cache.Org.getPartition(this.partitionName).remove(key);
    }
  }

  public virtual inherited sharing class Org extends Partition {
    public Org(String partitionName) {
      super(partitionName);
    }

    public override virtual Object get(String key) {
      return PlatformCache.partition.org(this.partitionName).get(key);
    }

    public override virtual void put(String key, Object value) {
      PlatformCache.partition.org(this.partitionName).put(key, value);
    }

    public override virtual void remove(String key) {
      PlatformCache.partition.org(this.partitionName).remove(key);
    }
  }

  public virtual inherited sharing class Session extends Partition {
    public Session(String partitionName) {
      super(partitionName);
    }

    public override virtual Object get(String key) {
      return PlatformCache.partition.session(this.partitionName).get(key);
    }

    public override virtual void put(String key, Object value) {
      PlatformCache.partition.session(this.partitionName).put(key, value);
    }

    public override virtual void remove(String key) {
      PlatformCache.partition.session(this.partitionName).remove(key);
    }
  }

  public inherited sharing class PartitionRegistry {
    Map<String, PlatformCache.Partition> partitions = new Map<String, PlatformCache.Partition>();

    void setMock(PlatformCache.Partition partitionMock) {
      this.setOrgMock(partitionMock);
    }

    void setOrgMock(PlatformCache.Partition partitionMock) {
      this.partitions.put(
        this.key(partitionMock.partitionName, PlatformCache.consts.ORG_SCOPE),
        partitionMock
      );
    }

    void setSessionMock(PlatformCache.Partition partitionMock) {
      this.partitions.put(
        this.key(
          partitionMock.partitionName,
          PlatformCache.consts.SESSION_SCOPE
        ),
        partitionMock
      );
    }

    PlatformCache.Partition org(String partitionName) {
      PlatformCache.Partition partitionMock = this.get(
        partitionName,
        PlatformCache.consts.ORG_SCOPE
      );
      if (partitionMock != null)
        return partitionMock;
      return new PlatformCache.Partition(partitionName);
    }

    PlatformCache.Partition session(String partitionName) {
      PlatformCache.Partition partitionMock = this.get(
        partitionName,
        PlatformCache.consts.SESSION_SCOPE
      );
      if (partitionMock != null)
        return partitionMock;
      return new PlatformCache.Partition(
        partitionName,
        PlatformCache.consts.SESSION_SCOPE
      );
    }

    PlatformCache.Partition get(String partitionName, String scope) {
      return this.partitions.get(this.key(partitionName, scope));
    }

    String key(String partitionName, String scope) {
      return scope + ':' + partitionName;
    }
  }

  public class Constants {
    public final String ORG_SCOPE = 'ORG';
    public final String SESSION_SCOPE = 'SESSION';
  }
}
