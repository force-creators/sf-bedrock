@istest(testFor='ApexClass:AsyncSettingsController')
public with sharing class AsyncSettingsControllerTest {
    @istest static void testGetSettings_returnsOrganizationAndUserSettings() {
        DML.insertRecords(new List<SObject> {
            new Async_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Archive_Threshold_Hours__c = 12,
                Enable_Archive_Cleanup__c = false,
                Max_Archive_Age__c = 30,
                Max_Threads__c = 3
            ),
            new Async_Settings__c(
                SetupOwnerId = UserInfo.getUserId(),
                Archive_Threshold_Hours__c = 0,
                Enable_Archive_Cleanup__c = true,
                Max_Archive_Age__c = 7,
                Max_Threads__c = 7
            )
        });

        Test.startTest();
        AsyncSettingsController.SettingsView view = AsyncSettingsController.getSettings(UserInfo.getUserId());
        Test.stopTest();

        Assert.isTrue(view.organization.hasRecord, 'Expected the settings view to include the organization custom setting row.');
        Assert.areEqual(12, view.organization.archiveThresholdHours, 'Expected the organization archive threshold value to be returned.');
        Assert.isFalse(view.organization.archiveCleanupEnabled, 'Expected the organization archive cleanup setting to be returned.');
        Assert.areEqual(30, view.organization.maxArchiveAgeDays, 'Expected the organization max archive age value to be returned.');
        Assert.areEqual(3, view.organization.maxThreads, 'Expected the organization setting max threads value to be returned.');
        Assert.isTrue(view.user.hasRecord, 'Expected the settings view to include the selected user custom setting row.');
        Assert.areEqual(0, view.user.archiveThresholdHours, 'Expected the user archive threshold value to allow zero.');
        Assert.isTrue(view.user.archiveCleanupEnabled, 'Expected the user archive cleanup setting to be returned.');
        Assert.areEqual(7, view.user.maxArchiveAgeDays, 'Expected the user max archive age value to be returned.');
        Assert.areEqual(7, view.user.maxThreads, 'Expected the user setting max threads value to be returned.');
        Assert.areEqual(1, view.userOverrides.size(), 'Expected the settings view to list user-owned custom setting overrides.');
        Assert.areEqual(0, view.effectiveArchiveThresholdHours, 'Expected the selected user archive threshold to override the organization setting.');
        Assert.isTrue(view.effectiveArchiveCleanupEnabled, 'Expected the selected user cleanup setting to override the organization setting.');
        Assert.areEqual(7, view.effectiveMaxArchiveAgeDays, 'Expected the selected user max archive age to override the organization setting.');
        Assert.areEqual(7, view.effectiveMaxThreads, 'Expected the selected user setting to override the organization setting.');
        Assert.areEqual(UserInfo.getUserId(), view.selectedUser.id, 'Expected the current user to be selected by default.');
    }

    @istest static void testSaveSettings_createsUserSetting() {
        Test.startTest();
        AsyncSettingsController.SettingsView view = AsyncSettingsController.saveSettings(
            'User',
            UserInfo.getUserId(),
            5,
            0,
            14,
            true
        );
        Test.stopTest();

        Async_Settings__c settings = [
            SELECT SetupOwnerId, Archive_Threshold_Hours__c, Enable_Archive_Cleanup__c, Max_Archive_Age__c, Max_Threads__c
            FROM Async_Settings__c
            WHERE SetupOwnerId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Assert.areEqual(UserInfo.getUserId(), settings.SetupOwnerId, 'Expected saveSettings to create a user-owned custom setting row.');
        Assert.areEqual(0, settings.Archive_Threshold_Hours__c, 'Expected saveSettings to persist a zero user archive threshold value.');
        Assert.isTrue(settings.Enable_Archive_Cleanup__c, 'Expected saveSettings to persist the requested user archive cleanup toggle.');
        Assert.areEqual(14, settings.Max_Archive_Age__c, 'Expected saveSettings to persist the requested user max archive age value.');
        Assert.areEqual(5, settings.Max_Threads__c, 'Expected saveSettings to persist the requested user max threads value.');
        Assert.isTrue(view.user.hasRecord, 'Expected the refreshed settings view to show the created user row.');
        Assert.areEqual(1, view.userOverrides.size(), 'Expected the refreshed settings view to include the created user override row.');
    }

    @istest static void testSaveSettings_updatesOrganizationSetting() {
        DML.insertRecords(new List<SObject> {
            new Async_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Archive_Threshold_Hours__c = 12,
                Enable_Archive_Cleanup__c = false,
                Max_Archive_Age__c = 30,
                Max_Threads__c = 2
            )
        });

        Test.startTest();
        AsyncSettingsController.saveSettings('Organization', null, 4, 72, 90, true);
        Test.stopTest();

        Async_Settings__c settings = [
            SELECT Archive_Threshold_Hours__c, Enable_Archive_Cleanup__c, Max_Archive_Age__c, Max_Threads__c
            FROM Async_Settings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1
        ];
        Assert.areEqual(72, settings.Archive_Threshold_Hours__c, 'Expected saveSettings to update the organization archive threshold value.');
        Assert.isTrue(settings.Enable_Archive_Cleanup__c, 'Expected saveSettings to update the organization archive cleanup toggle.');
        Assert.areEqual(90, settings.Max_Archive_Age__c, 'Expected saveSettings to update the organization max archive age value.');
        Assert.areEqual(4, settings.Max_Threads__c, 'Expected saveSettings to update the organization max threads value.');
    }

    @istest static void testDeleteUserSettings_removesUserOverride() {
        DML.insertRecords(new List<SObject> {
            new Async_Settings__c(
                SetupOwnerId = UserInfo.getUserId(),
                Max_Threads__c = 6
            )
        });

        Test.startTest();
        AsyncSettingsController.SettingsView view = AsyncSettingsController.deleteUserSettings(UserInfo.getUserId());
        Test.stopTest();

        Integer settingsCount = [
            SELECT COUNT()
            FROM Async_Settings__c
            WHERE SetupOwnerId = :UserInfo.getUserId()
        ];
        Assert.areEqual(0, settingsCount, 'Expected deleteUserSettings to remove the user-owned custom setting row.');
        Assert.isFalse(view.user.hasRecord, 'Expected the refreshed settings view to show no user setting row.');
        Assert.areEqual(0, view.userOverrides.size(), 'Expected the refreshed settings view to remove the deleted user override row.');
    }

    @istest static void testSearchUsers_returnsCurrentUserForMatchingTerm() {
        String username = UserInfo.getUserName();
        String searchTerm = username.substring(0, Math.min(3, username.length()));

        Test.startTest();
        List<AsyncSettingsController.UserOption> users = AsyncSettingsController.searchUsers(searchTerm);
        Test.stopTest();

        Set<Id> userIds = new Set<Id>();
        for (AsyncSettingsController.UserOption userOption : users) {
            userIds.add(userOption.id);
        }

        Assert.isTrue(userIds.contains(UserInfo.getUserId()), 'Expected user search to return the current user for a matching username fragment.');
    }
}
