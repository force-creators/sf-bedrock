/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:Generic')
private class GenericTest {
  @istest
  static void testDefaultConstructor_putAndGetPath() {
    Generic generic = new Generic();
    generic.put('user.profile.firstName', 'Bedrock');

    Assert.areEqual(
      'Bedrock',
      generic.get('user.profile.firstName'),
      'Expected put to create nested map values and get to return the inserted value from the same path.'
    );
  }

  @istest
  static void testConstructorFromJson_getPath() {
    Generic generic = new Generic(
      '{"user":{"name":"Alice","tags":["admin","beta"]}}'
    );

    Assert.areEqual(
      'Alice',
      generic.get('user.name'),
      'Expected JSON constructor to hydrate nested object values.'
    );
    Assert.areEqual(
      'admin',
      generic.get('user.tags[0]'),
      'Expected bracket notation path to access list values in hydrated JSON.'
    );
  }

  @istest
  static void testGetWithTargetTypeCoercion() {
    Generic generic = new Generic(
      new Map<String, Object>{
        'count' => '42',
        'enabled' => 'true',
        'amount' => '10.50'
      }
    );

    Assert.areEqual(
      42,
      (Integer) generic.get('count', Integer.class),
      'Expected typed get to coerce numeric string values into Integer.'
    );
    Assert.areEqual(
      true,
      (Boolean) generic.get('enabled', Boolean.class),
      'Expected typed get to coerce boolean string values into Boolean.'
    );
    Assert.areEqual(
      10.50,
      (Decimal) generic.get('amount', Decimal.class),
      'Expected typed get to coerce decimal string values into Decimal.'
    );
  }

  @istest
  static void testJsonAndSObjectConversion() {
    Generic generic = new Generic();
    generic.put('Name', 'Acme');

    String json = generic.json();
    Account account = (Account) generic.sObject(Account.class);

    Assert.isTrue(
      json.contains('"Name":"Acme"'),
      'Expected json() to serialize inserted values.'
    );
    Assert.areEqual(
      'Acme',
      account.Name,
      'Expected sObject conversion to map Name into an Account instance.'
    );
  }

  @istest
  static void testConstructorFromMap_copiesInput() {
    Map<String, Object> source = new Map<String, Object>{
      'status' => 'initial'
    };
    Generic generic = new Generic(source);
    source.put('status', 'changed');

    Assert.areEqual(
      'initial',
      generic.get('status'),
      'Expected map constructor to copy input entries so later source mutations do not change Generic state.'
    );
  }

  @istest
  static void testPutMap_appliesMultiplePaths() {
    Generic generic = new Generic();
    generic.put(
      new Map<String, Object>{
        'user.firstName' => 'Ada',
        'user.lastName' => 'Lovelace'
      }
    );

    Assert.areEqual(
      'Ada',
      generic.get('user.firstName'),
      'Expected put(Map) to apply the first provided path.'
    );
    Assert.areEqual(
      'Lovelace',
      generic.get('user.lastName'),
      'Expected put(Map) to apply the second provided path.'
    );
  }

  @istest
  static void testGet_missingPathAndOutOfBoundsReturnNull() {
    Generic generic = new Generic('{"user":{"tags":["admin"]}}');

    Assert.areEqual(
      null,
      generic.get('user.missing'),
      'Expected get to return null when a map path segment does not exist.'
    );
    Assert.areEqual(
      null,
      generic.get('user.tags[2]'),
      'Expected get to return null when a list index is out of bounds.'
    );
  }

  @istest
  static void testGetWithTargetType_coercesDateAndDatetime() {
    Generic generic = new Generic(
      new Map<String, Object>{
        'startDate' => '2026-01-15',
        'runAt' => '2026-01-15 10:30:00'
      }
    );

    Assert.areEqual(
      Date.newInstance(2026, 1, 15),
      (Date) generic.get('startDate', Date.class),
      'Expected typed get to coerce ISO date strings into Date values.'
    );
    Assert.areEqual(
      Datetime.newInstance(2026, 1, 15, 10, 30, 0),
      (Datetime) generic.get('runAt', Datetime.class),
      'Expected typed get to coerce datetime strings into Datetime values.'
    );
  }

  @istest
  static void testGetWithTargetType_listOfMaps() {
    Generic generic = new Generic('{"items":[{"name":"A"},{"name":"B"}]}');

    List<Map<String, Object>> items = (List<Map<String, Object>>) generic.get(
      'items',
      List<Map<String, Object>>.class
    );

    Assert.areEqual(
      2,
      items.size(),
      'Expected typed get to coerce a list payload into List<Map<String, Object>>.'
    );
    Assert.areEqual(
      'B',
      items[1].get('name'),
      'Expected typed list coercion to preserve map values for each list item.'
    );
  }

  @istest
  static void testDefaultMappingAndTransformAreEmpty() {
    Generic generic = new Generic();

    Assert.areEqual(
      0,
      generic.mapping().size(),
      'Expected default mapping implementation to return an empty map.'
    );
    Assert.areEqual(
      0,
      generic.transform().size(),
      'Expected default transform implementation to return an empty map.'
    );
  }

  @istest
  static void testTransformUsesMapping() {
    Generic transformed = new GenericMappingExample();

    Map<String, Object> value = transformed.transform();

    Assert.areEqual(
      'ready',
      value.get('status'),
      'Expected transform to return a map built from mapping values.'
    );
    Assert.areEqual(
      1,
      value.get('version'),
      'Expected transform to preserve numeric values from mapping output.'
    );
  }

  private inherited sharing class GenericMappingExample extends Generic {
    public override Map<String, Object> mapping() {
      return new Map<String, Object>{ 'status' => 'ready', 'version' => 1 };
    }
  }
}
