/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:ThreadSettingsController')
public with sharing class ThreadSettingsControllerTest {
  @istest
  static void testGetSettings_returnsOrganizationAndUserSettings() {
    DML.insertRecords(
      new List<SObject>{
        new Thread_Settings__c(
          SetupOwnerId = UserInfo.getOrganizationId(),
          Enable_Recovery__c = true,
          Max_Threads__c = 3,
          Recovery_Batch_Size__c = 11,
          Recovery_Limit_Threshold_Pct__c = 80,
          Recovery_Threshold_Minutes__c = 15
        ),
        new Thread_Settings__c(
          SetupOwnerId = UserInfo.getUserId(),
          Enable_Recovery__c = false,
          Max_Threads__c = 7,
          Recovery_Batch_Size__c = 5,
          Recovery_Limit_Threshold_Pct__c = 50,
          Recovery_Threshold_Minutes__c = 2
        )
      }
    );

    Test.startTest();
    ThreadSettingsController.SettingsView view = ThreadSettingsController.getSettings(
      UserInfo.getUserId()
    );
    Test.stopTest();

    Assert.isTrue(
      view.organization.hasRecord,
      'Expected the settings view to include the organization custom setting row.'
    );
    Assert.isTrue(
      view.organization.recoveryEnabled,
      'Expected the organization recovery toggle to be returned.'
    );
    Assert.areEqual(
      3,
      view.organization.maxThreads,
      'Expected the organization max threads value to be returned.'
    );
    Assert.areEqual(
      11,
      view.organization.recoveryBatchSize,
      'Expected the organization recovery batch size to be returned.'
    );
    Assert.areEqual(
      80,
      view.organization.recoveryLimitThresholdPct,
      'Expected the organization recovery limit threshold to be returned.'
    );
    Assert.areEqual(
      15,
      view.organization.recoveryThresholdMinutes,
      'Expected the organization recovery threshold to be returned.'
    );
    Assert.isTrue(
      view.user.hasRecord,
      'Expected the settings view to include the selected user custom setting row.'
    );
    Assert.isFalse(
      view.user.recoveryEnabled,
      'Expected the user recovery toggle to override the organization setting.'
    );
    Assert.areEqual(
      7,
      view.effectiveMaxThreads,
      'Expected the selected user setting to override max threads.'
    );
    Assert.areEqual(
      5,
      view.effectiveRecoveryBatchSize,
      'Expected the selected user setting to override recovery batch size.'
    );
    Assert.areEqual(
      50,
      view.effectiveRecoveryLimitThresholdPct,
      'Expected the selected user setting to override recovery limit threshold.'
    );
    Assert.areEqual(
      2,
      view.effectiveRecoveryThresholdMinutes,
      'Expected the selected user setting to override recovery threshold.'
    );
    Assert.areEqual(
      1,
      view.userOverrides.size(),
      'Expected the settings view to list user-owned custom setting overrides.'
    );
    Assert.areEqual(
      UserInfo.getUserId(),
      view.selectedUser.id,
      'Expected the current user to be selected by default.'
    );
  }

  @istest
  static void testSaveSettings_createsUserSetting() {
    Test.startTest();
    ThreadSettingsController.SettingsView view = ThreadSettingsController.saveSettings(
      'User',
      UserInfo.getUserId(),
      5,
      20,
      12,
      75,
      true
    );
    Test.stopTest();

    Thread_Settings__c settings = [
      SELECT
        SetupOwnerId,
        Enable_Recovery__c,
        Max_Threads__c,
        Recovery_Batch_Size__c,
        Recovery_Limit_Threshold_Pct__c,
        Recovery_Threshold_Minutes__c
      FROM Thread_Settings__c
      WHERE SetupOwnerId = :UserInfo.getUserId()
      LIMIT 1
    ];
    Assert.areEqual(
      UserInfo.getUserId(),
      settings.SetupOwnerId,
      'Expected saveSettings to create a user-owned custom setting row.'
    );
    Assert.isTrue(
      settings.Enable_Recovery__c,
      'Expected saveSettings to persist the requested recovery toggle.'
    );
    Assert.areEqual(
      5,
      settings.Max_Threads__c,
      'Expected saveSettings to persist max threads.'
    );
    Assert.areEqual(
      12,
      settings.Recovery_Batch_Size__c,
      'Expected saveSettings to persist recovery batch size.'
    );
    Assert.areEqual(
      75,
      settings.Recovery_Limit_Threshold_Pct__c,
      'Expected saveSettings to persist recovery limit threshold.'
    );
    Assert.areEqual(
      20,
      settings.Recovery_Threshold_Minutes__c,
      'Expected saveSettings to persist recovery threshold.'
    );
    Assert.isTrue(
      view.user.hasRecord,
      'Expected the refreshed settings view to show the created user row.'
    );
    Assert.areEqual(
      1,
      view.userOverrides.size(),
      'Expected the refreshed settings view to include the created user override row.'
    );
  }

  @istest
  static void testSaveSettings_updatesOrganizationSetting() {
    DML.insertRecords(
      new List<SObject>{
        new Thread_Settings__c(
          SetupOwnerId = UserInfo.getOrganizationId(),
          Max_Threads__c = 2
        )
      }
    );

    Test.startTest();
    ThreadSettingsController.saveSettings(
      'Organization',
      null,
      4,
      30,
      20,
      60,
      false
    );
    Test.stopTest();

    Thread_Settings__c settings = [
      SELECT
        Enable_Recovery__c,
        Max_Threads__c,
        Recovery_Batch_Size__c,
        Recovery_Limit_Threshold_Pct__c,
        Recovery_Threshold_Minutes__c
      FROM Thread_Settings__c
      WHERE SetupOwnerId = :UserInfo.getOrganizationId()
      LIMIT 1
    ];
    Assert.isFalse(
      settings.Enable_Recovery__c,
      'Expected saveSettings to update the organization recovery toggle.'
    );
    Assert.areEqual(
      4,
      settings.Max_Threads__c,
      'Expected saveSettings to update max threads.'
    );
    Assert.areEqual(
      20,
      settings.Recovery_Batch_Size__c,
      'Expected saveSettings to update recovery batch size.'
    );
    Assert.areEqual(
      60,
      settings.Recovery_Limit_Threshold_Pct__c,
      'Expected saveSettings to update recovery limit threshold.'
    );
    Assert.areEqual(
      30,
      settings.Recovery_Threshold_Minutes__c,
      'Expected saveSettings to update recovery threshold.'
    );
  }

  @istest
  static void testDeleteUserSettings_removesUserOverride() {
    DML.insertRecords(
      new List<SObject>{
        new Thread_Settings__c(
          SetupOwnerId = UserInfo.getUserId(),
          Max_Threads__c = 6
        )
      }
    );

    Test.startTest();
    ThreadSettingsController.SettingsView view = ThreadSettingsController.deleteUserSettings(
      UserInfo.getUserId()
    );
    Test.stopTest();

    Integer settingsCount = [
      SELECT COUNT()
      FROM Thread_Settings__c
      WHERE SetupOwnerId = :UserInfo.getUserId()
    ];
    Assert.areEqual(
      0,
      settingsCount,
      'Expected deleteUserSettings to remove the user-owned custom setting row.'
    );
    Assert.isFalse(
      view.user.hasRecord,
      'Expected the refreshed settings view to show no user setting row.'
    );
    Assert.areEqual(
      0,
      view.userOverrides.size(),
      'Expected the refreshed settings view to remove the deleted user override row.'
    );
  }

  @istest
  static void testSearchUsers_returnsCurrentUserForMatchingTerm() {
    String username = UserInfo.getUserName();
    String searchTerm = username.substring(0, Math.min(3, username.length()));

    Test.startTest();
    List<ThreadSettingsController.UserOption> users = ThreadSettingsController.searchUsers(
      searchTerm
    );
    Test.stopTest();

    Set<Id> userIds = new Set<Id>();
    for (ThreadSettingsController.UserOption userOption : users) {
      userIds.add(userOption.id);
    }

    Assert.isTrue(
      userIds.contains(UserInfo.getUserId()),
      'Expected user search to return the current user for a matching username fragment.'
    );
  }
}
