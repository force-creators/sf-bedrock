/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class AsyncSettingsController {
    static final Integer USER_SEARCH_LIMIT = 10;

    @AuraEnabled
    public static SettingsView getSettings(Id userId) {
        Id selectedUserId = userId == null ? UserInfo.getUserId() : userId;
        Id organizationId = UserInfo.getOrganizationId();

        SettingsView view = new SettingsView();
        view.organization = new SettingsRow(
            getRawSetting(organizationId),
            organizationId,
            'Organization'
        );
        view.user = new SettingsRow(
            getRawSetting(selectedUserId),
            selectedUserId,
            'User'
        );
        view.userOverrides = getUserOverrides(organizationId);
        view.currentUser = new UserOption(currentUser());
        view.selectedUser = new UserOption(selectedUser(selectedUserId));
        view.effectiveMaxThreads = maxThreads(
            Async_Settings__c.getInstance(selectedUserId)
        );
        view.effectiveArchiveThresholdHours = archiveThresholdHours(
            Async_Settings__c.getInstance(selectedUserId)
        );
        view.effectiveMaxArchiveAgeDays = maxArchiveAgeDays(
            Async_Settings__c.getInstance(selectedUserId)
        );
        view.effectiveArchiveCleanupEnabled = archiveCleanupEnabled(
            Async_Settings__c.getInstance(selectedUserId)
        );
        return view;
    }

    @AuraEnabled
    public static List<UserOption> searchUsers(String searchTerm) {
        String normalizedSearchTerm = String.isBlank(searchTerm)
            ? null
            : searchTerm.trim();

        if (normalizedSearchTerm == null || normalizedSearchTerm.length() < 2) {
            return new List<UserOption>{ new UserOption(currentUser()) };
        }

        String searchPattern = '%' + normalizedSearchTerm + '%';
        List<UserOption> options = new List<UserOption>();

        for (User userRecord : [
            SELECT Id, Name, Username, Email
            FROM User
            WHERE
                IsActive = TRUE
                AND (Name LIKE :searchPattern
                OR Username LIKE :searchPattern
                OR Email LIKE :searchPattern)
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT :USER_SEARCH_LIMIT
        ]) {
            options.add(new UserOption(userRecord));
        }

        return options;
    }

    @AuraEnabled
    public static SettingsView saveSettings(
        String scope,
        Id userId,
        Decimal maxThreads,
        Decimal archiveThresholdHours,
        Decimal maxArchiveAgeDays,
        Boolean archiveCleanupEnabled
    ) {
        if (String.isBlank(scope)) {
            throw new AuraHandledException(
                'Choose a settings scope before saving.'
            );
        }

        if (maxThreads != null && (maxThreads < 1 || maxThreads > 99999)) {
            throw new AuraHandledException(
                'Max threads must be blank or between 1 and 99999.'
            );
        }

        if (
            archiveThresholdHours != null &&
            (archiveThresholdHours < 0 ||
            archiveThresholdHours > 99999)
        ) {
            throw new AuraHandledException(
                'Archive threshold hours must be blank or between 0 and 99999.'
            );
        }

        if (
            maxArchiveAgeDays != null &&
            (maxArchiveAgeDays < 0 ||
            maxArchiveAgeDays > 99999)
        ) {
            throw new AuraHandledException(
                'Max archive age must be blank or between 0 and 99999 days.'
            );
        }

        Id setupOwnerId = setupOwnerId(scope, userId);
        Async_Settings__c existingSettings = getRawSetting(setupOwnerId);
        Async_Settings__c settings = existingSettings == null
            ? new Async_Settings__c(SetupOwnerId = setupOwnerId)
            : new Async_Settings__c(Id = existingSettings.Id);
        settings.Archive_Threshold_Hours__c = archiveThresholdHours;
        settings.Enable_Archive_Cleanup__c = archiveCleanupEnabled == true;
        settings.Max_Archive_Age__c = maxArchiveAgeDays;
        settings.Max_Threads__c = maxThreads;

        saveSettingsRecord(settings, existingSettings == null);
        return getSettings(scope == 'User' ? userId : null);
    }

    @AuraEnabled
    public static SettingsView deleteUserSettings(Id userId) {
        if (userId == null) {
            throw new AuraHandledException(
                'Choose a user before deleting user settings.'
            );
        }

        Async_Settings__c settings = getRawSetting(userId);

        if (settings != null) {
            assertCanDelete();
            delete settings;
        }

        return getSettings(userId);
    }

    static Id setupOwnerId(String scope, Id userId) {
        if (scope == 'Organization') {
            return UserInfo.getOrganizationId();
        }

        if (scope == 'User' && userId != null) {
            return userId;
        }

        throw new AuraHandledException(
            'Choose a user before saving user settings.'
        );
    }

    static void saveSettingsRecord(Async_Settings__c settings, Boolean isNew) {
        if (isNew) {
            assertCanCreate();
            insert settings;
            return;
        }

        assertCanUpdate();
        update settings;
    }

    static void assertCanCreate() {
        if (
            !Schema.sObjectType.Async_Settings__c.isCreateable() ||
            !Schema.sObjectType.Async_Settings__c.fields.Archive_Threshold_Hours__c.isCreateable() ||
            !Schema.sObjectType.Async_Settings__c.fields.Enable_Archive_Cleanup__c.isCreateable() ||
            !Schema.sObjectType.Async_Settings__c.fields.Max_Archive_Age__c.isCreateable() ||
            !Schema.sObjectType.Async_Settings__c.fields.Max_Threads__c.isCreateable()
        ) {
            throw new AuraHandledException(
                'You do not have permission to create async settings.'
            );
        }
    }

    static void assertCanUpdate() {
        if (
            !Schema.sObjectType.Async_Settings__c.isUpdateable() ||
            !Schema.sObjectType.Async_Settings__c.fields.Archive_Threshold_Hours__c.isUpdateable() ||
            !Schema.sObjectType.Async_Settings__c.fields.Enable_Archive_Cleanup__c.isUpdateable() ||
            !Schema.sObjectType.Async_Settings__c.fields.Max_Archive_Age__c.isUpdateable() ||
            !Schema.sObjectType.Async_Settings__c.fields.Max_Threads__c.isUpdateable()
        ) {
            throw new AuraHandledException(
                'You do not have permission to update async settings.'
            );
        }
    }

    static void assertCanDelete() {
        if (!Schema.sObjectType.Async_Settings__c.isDeletable()) {
            throw new AuraHandledException(
                'You do not have permission to delete async settings.'
            );
        }
    }

    static Async_Settings__c getRawSetting(Id setupOwnerId) {
        List<Async_Settings__c> settings = [
            SELECT
                Id,
                SetupOwnerId,
                Archive_Threshold_Hours__c,
                Enable_Archive_Cleanup__c,
                Max_Archive_Age__c,
                Max_Threads__c
            FROM Async_Settings__c
            WHERE SetupOwnerId = :setupOwnerId
            WITH USER_MODE
            LIMIT 1
        ];
        return settings.isEmpty() ? null : settings[0];
    }

    static List<UserSettingRow> getUserOverrides(Id organizationId) {
        List<Async_Settings__c> settings = [
            SELECT
                Id,
                SetupOwnerId,
                Archive_Threshold_Hours__c,
                Enable_Archive_Cleanup__c,
                Max_Archive_Age__c,
                Max_Threads__c
            FROM Async_Settings__c
            WHERE SetupOwnerId != :organizationId
            WITH USER_MODE
            LIMIT 200
        ];
        Map<Id, Async_Settings__c> settingsByUserId = new Map<Id, Async_Settings__c>();

        for (Async_Settings__c setting : settings) {
            if (String.valueOf(setting.SetupOwnerId).startsWith('005')) {
                settingsByUserId.put(setting.SetupOwnerId, setting);
            }
        }

        if (settingsByUserId.isEmpty()) {
            return new List<UserSettingRow>();
        }

        List<UserSettingRow> rows = new List<UserSettingRow>();
        for (User userRecord : [
            SELECT Id, Name, Username, Email
            FROM User
            WHERE Id IN :settingsByUserId.keySet()
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            rows.add(
                new UserSettingRow(
                    settingsByUserId.get(userRecord.Id),
                    userRecord
                )
            );
        }

        return rows;
    }

    static User currentUser() {
        return selectedUser(UserInfo.getUserId());
    }

    static User selectedUser(Id userId) {
        return [
            SELECT Id, Name, Username, Email
            FROM User
            WHERE Id = :userId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    static Integer maxThreads(Async_Settings__c settings) {
        Decimal maxThreads = settings == null ? null : settings.Max_Threads__c;
        return maxThreads == null || maxThreads < 1 ? 1 : maxThreads.intValue();
    }

    static Integer archiveThresholdHours(Async_Settings__c settings) {
        Decimal threshold = settings == null
            ? null
            : settings.Archive_Threshold_Hours__c;
        return threshold == null || threshold < 0 ? 24 : threshold.intValue();
    }

    static Boolean archiveCleanupEnabled(Async_Settings__c settings) {
        return settings != null && settings.Enable_Archive_Cleanup__c == true;
    }

    static Integer maxArchiveAgeDays(Async_Settings__c settings) {
        Decimal maxArchiveAge = settings == null
            ? null
            : settings.Max_Archive_Age__c;
        return maxArchiveAge == null ||
            maxArchiveAge < 0
            ? 30
            : maxArchiveAge.intValue();
    }

    public class SettingsView {
        @AuraEnabled
        public SettingsRow organization;
        @AuraEnabled
        public SettingsRow user;
        @AuraEnabled
        public List<UserSettingRow> userOverrides = new List<UserSettingRow>();
        @AuraEnabled
        public UserOption currentUser;
        @AuraEnabled
        public UserOption selectedUser;
        @AuraEnabled
        public Boolean effectiveArchiveCleanupEnabled;
        @AuraEnabled
        public Integer effectiveArchiveThresholdHours;
        @AuraEnabled
        public Integer effectiveMaxArchiveAgeDays;
        @AuraEnabled
        public Integer effectiveMaxThreads;
    }

    public class SettingsRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id setupOwnerId;
        @AuraEnabled
        public String scope;
        @AuraEnabled
        public Decimal archiveThresholdHours;
        @AuraEnabled
        public Boolean archiveCleanupEnabled;
        @AuraEnabled
        public Decimal maxArchiveAgeDays;
        @AuraEnabled
        public Decimal maxThreads;
        @AuraEnabled
        public Boolean hasRecord;

        SettingsRow(Async_Settings__c settings, Id setupOwnerId, String scope) {
            this.id = settings == null ? null : settings.Id;
            this.setupOwnerId = setupOwnerId;
            this.scope = scope;
            this.archiveThresholdHours = settings == null
                ? null
                : settings.Archive_Threshold_Hours__c;
            this.archiveCleanupEnabled = settings == null
                ? false
                : settings.Enable_Archive_Cleanup__c;
            this.maxArchiveAgeDays = settings == null
                ? null
                : settings.Max_Archive_Age__c;
            this.maxThreads = settings == null ? null : settings.Max_Threads__c;
            this.hasRecord = settings != null;
        }
    }

    public class UserSettingRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id setupOwnerId;
        @AuraEnabled
        public Decimal archiveThresholdHours;
        @AuraEnabled
        public Boolean archiveCleanupEnabled;
        @AuraEnabled
        public Decimal maxArchiveAgeDays;
        @AuraEnabled
        public Decimal maxThreads;
        @AuraEnabled
        public Boolean hasRecord;
        @AuraEnabled
        public UserOption user;

        UserSettingRow(Async_Settings__c settings, User userRecord) {
            this.id = settings.Id;
            this.setupOwnerId = settings.SetupOwnerId;
            this.archiveThresholdHours = settings.Archive_Threshold_Hours__c;
            this.archiveCleanupEnabled = settings.Enable_Archive_Cleanup__c;
            this.maxArchiveAgeDays = settings.Max_Archive_Age__c;
            this.maxThreads = settings.Max_Threads__c;
            this.hasRecord = true;
            this.user = new UserOption(userRecord);
        }
    }

    public class UserOption {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String username;
        @AuraEnabled
        public String email;

        UserOption(User userRecord) {
            this.id = userRecord.Id;
            this.label = userRecord.Name;
            this.username = userRecord.Username;
            this.email = userRecord.Email;
        }
    }
}
