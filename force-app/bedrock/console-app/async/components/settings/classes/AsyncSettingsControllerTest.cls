@istest(testFor='ApexClass:AsyncSettingsController')
public with sharing class AsyncSettingsControllerTest {
    @istest static void testGetSettings_returnsOrganizationAndUserSettings() {
        DML.insertRecords(new List<SObject> {
            new Async_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Max_Threads__c = 3
            ),
            new Async_Settings__c(
                SetupOwnerId = UserInfo.getUserId(),
                Max_Threads__c = 7
            )
        });

        Test.startTest();
        AsyncSettingsController.SettingsView view = AsyncSettingsController.getSettings(UserInfo.getUserId());
        Test.stopTest();

        Assert.isTrue(view.organization.hasRecord, 'Expected the settings view to include the organization custom setting row.');
        Assert.areEqual(3, view.organization.maxThreads, 'Expected the organization setting max threads value to be returned.');
        Assert.isTrue(view.user.hasRecord, 'Expected the settings view to include the selected user custom setting row.');
        Assert.areEqual(7, view.user.maxThreads, 'Expected the user setting max threads value to be returned.');
        Assert.areEqual(1, view.userOverrides.size(), 'Expected the settings view to list user-owned custom setting overrides.');
        Assert.areEqual(7, view.effectiveMaxThreads, 'Expected the selected user setting to override the organization setting.');
        Assert.areEqual(UserInfo.getUserId(), view.selectedUser.id, 'Expected the current user to be selected by default.');
    }

    @istest static void testSaveSettings_createsUserSetting() {
        Test.startTest();
        AsyncSettingsController.SettingsView view = AsyncSettingsController.saveSettings(
            'User',
            UserInfo.getUserId(),
            5
        );
        Test.stopTest();

        Async_Settings__c settings = [
            SELECT SetupOwnerId, Max_Threads__c
            FROM Async_Settings__c
            WHERE SetupOwnerId = :UserInfo.getUserId()
            LIMIT 1
        ];
        Assert.areEqual(UserInfo.getUserId(), settings.SetupOwnerId, 'Expected saveSettings to create a user-owned custom setting row.');
        Assert.areEqual(5, settings.Max_Threads__c, 'Expected saveSettings to persist the requested user max threads value.');
        Assert.isTrue(view.user.hasRecord, 'Expected the refreshed settings view to show the created user row.');
        Assert.areEqual(1, view.userOverrides.size(), 'Expected the refreshed settings view to include the created user override row.');
    }

    @istest static void testSaveSettings_updatesOrganizationSetting() {
        DML.insertRecords(new List<SObject> {
            new Async_Settings__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Max_Threads__c = 2
            )
        });

        Test.startTest();
        AsyncSettingsController.saveSettings('Organization', null, 4);
        Test.stopTest();

        Async_Settings__c settings = [
            SELECT Max_Threads__c
            FROM Async_Settings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1
        ];
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
