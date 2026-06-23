/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public inherited sharing class PlatformCacheMock extends PlatformCache.Partition {
  public Map<String, Object> valuesByKey = new Map<String, Object>();
  public List<String> gets = new List<String>();
  public List<String> puts = new List<String>();
  public List<String> removes = new List<String>();

  public PlatformCacheMock(String partitionName) {
    super(partitionName);
  }

  public override Object get(String key) {
    this.gets.add(key);
    return this.valuesByKey.get(key);
  }

  public override void put(String key, Object value) {
    this.puts.add(key);
    this.valuesByKey.put(key, value);
  }

  public override void remove(String key) {
    this.removes.add(key);
    this.valuesByKey.remove(key);
  }
}
