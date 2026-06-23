/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class ThreadSettingsController {
    static final Integer USER_SEARCH_LIMIT = 10;

    @AuraEnabled
    public static SettingsView getSettings(Id userId) {
        Id selectedUserId = userId == null ? UserInfo.getUserId() : userId;
        Id organizationId = UserInfo.getOrganizationId();
        Thread_Settings__c effectiveSettings = Thread_Settings__c.getInstance(
            selectedUserId
        );

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
        view.effectiveMaxThreads = maxThreads(effectiveSettings);
        view.effectiveRecoveryThresholdMinutes = recoveryThresholdMinutes(
            effectiveSettings
        );
        view.effectiveRecoveryBatchSize = recoveryBatchSize(effectiveSettings);
        view.effectiveRecoveryLimitThresholdPct = recoveryLimitThresholdPct(
            effectiveSettings
        );
        view.effectiveRecoveryEnabled = recoveryEnabled(effectiveSettings);
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
        Decimal recoveryThresholdMinutes,
        Decimal recoveryBatchSize,
        Decimal recoveryLimitThresholdPct,
        Boolean recoveryEnabled
    ) {
        if (String.isBlank(scope)) {
            throw new AuraHandledException(
                'Choose a settings scope before saving.'
            );
        }

        validateRange(maxThreads, 'Max threads', 1, 99999);
        validateRange(
            recoveryThresholdMinutes,
            'Recovery threshold minutes',
            1,
            99999
        );
        validateRange(recoveryBatchSize, 'Recovery batch size', 1, 99999);
        validateRange(
            recoveryLimitThresholdPct,
            'Recovery limit threshold percent',
            1,
            100
        );

        Id setupOwnerId = setupOwnerId(scope, userId);
        Thread_Settings__c existingSettings = getRawSetting(setupOwnerId);
        Thread_Settings__c settings = existingSettings == null
            ? new Thread_Settings__c(SetupOwnerId = setupOwnerId)
            : new Thread_Settings__c(Id = existingSettings.Id);
        settings.Enable_Recovery__c = recoveryEnabled == true;
        settings.Max_Threads__c = maxThreads;
        settings.Recovery_Batch_Size__c = recoveryBatchSize;
        settings.Recovery_Limit_Threshold_Pct__c = recoveryLimitThresholdPct;
        settings.Recovery_Threshold_Minutes__c = recoveryThresholdMinutes;

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

        Thread_Settings__c settings = getRawSetting(userId);

        if (settings != null) {
            assertCanDelete();
            DML.deleteRecords(new List<SObject>{ settings });
        }

        return getSettings(userId);
    }

    static void validateRange(
        Decimal value,
        String label,
        Integer minimum,
        Integer maximum
    ) {
        if (value != null && (value < minimum || value > maximum)) {
            throw new AuraHandledException(
                label +
                    ' must be blank or between ' +
                    minimum +
                    ' and ' +
                    maximum +
                    '.'
            );
        }
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

    static void saveSettingsRecord(Thread_Settings__c settings, Boolean isNew) {
        if (isNew) {
            assertCanCreate();
            DML.insertRecords(new List<SObject>{ settings });
            return;
        }

        assertCanUpdate();
        DML.updateRecords(new List<SObject>{ settings });
    }

    static void assertCanCreate() {
        if (
            !Schema.sObjectType.Thread_Settings__c.isCreateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Enable_Recovery__c.isCreateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Max_Threads__c.isCreateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Recovery_Batch_Size__c.isCreateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Recovery_Limit_Threshold_Pct__c.isCreateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Recovery_Threshold_Minutes__c.isCreateable()
        ) {
            throw new AuraHandledException(
                'You do not have permission to create thread settings.'
            );
        }
    }

    static void assertCanUpdate() {
        if (
            !Schema.sObjectType.Thread_Settings__c.isUpdateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Enable_Recovery__c.isUpdateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Max_Threads__c.isUpdateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Recovery_Batch_Size__c.isUpdateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Recovery_Limit_Threshold_Pct__c.isUpdateable() ||
            !Schema.sObjectType.Thread_Settings__c.fields.Recovery_Threshold_Minutes__c.isUpdateable()
        ) {
            throw new AuraHandledException(
                'You do not have permission to update thread settings.'
            );
        }
    }

    static void assertCanDelete() {
        if (!Schema.sObjectType.Thread_Settings__c.isDeletable()) {
            throw new AuraHandledException(
                'You do not have permission to delete thread settings.'
            );
        }
    }

    static Thread_Settings__c getRawSetting(Id setupOwnerId) {
        List<Thread_Settings__c> settings = [
            SELECT
                Id,
                SetupOwnerId,
                Enable_Recovery__c,
                Max_Threads__c,
                Recovery_Batch_Size__c,
                Recovery_Limit_Threshold_Pct__c,
                Recovery_Threshold_Minutes__c
            FROM Thread_Settings__c
            WHERE SetupOwnerId = :setupOwnerId
            WITH USER_MODE
            LIMIT 1
        ];
        return settings.isEmpty() ? null : settings[0];
    }

    static List<UserSettingRow> getUserOverrides(Id organizationId) {
        List<Thread_Settings__c> settings = [
            SELECT
                Id,
                SetupOwnerId,
                Enable_Recovery__c,
                Max_Threads__c,
                Recovery_Batch_Size__c,
                Recovery_Limit_Threshold_Pct__c,
                Recovery_Threshold_Minutes__c
            FROM Thread_Settings__c
            WHERE SetupOwnerId != :organizationId
            WITH USER_MODE
            LIMIT 200
        ];
        Map<Id, Thread_Settings__c> settingsByUserId = new Map<Id, Thread_Settings__c>();

        for (Thread_Settings__c setting : settings) {
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

    static Integer maxThreads(Thread_Settings__c settings) {
        Decimal maxThreads = settings == null ? null : settings.Max_Threads__c;
        return maxThreads == null || maxThreads < 1 ? 1 : maxThreads.intValue();
    }

    static Integer recoveryThresholdMinutes(Thread_Settings__c settings) {
        Decimal threshold = settings == null
            ? null
            : settings.Recovery_Threshold_Minutes__c;
        return threshold == null || threshold < 1 ? 10 : threshold.intValue();
    }

    static Integer recoveryBatchSize(Thread_Settings__c settings) {
        Decimal batchSize = settings == null
            ? null
            : settings.Recovery_Batch_Size__c;
        return batchSize == null || batchSize < 1 ? 10 : batchSize.intValue();
    }

    static Integer recoveryLimitThresholdPct(Thread_Settings__c settings) {
        Decimal threshold = settings == null
            ? null
            : settings.Recovery_Limit_Threshold_Pct__c;
        return threshold == null || threshold < 1 ? 90 : threshold.intValue();
    }

    static Boolean recoveryEnabled(Thread_Settings__c settings) {
        return settings == null ||
            !settings.getPopulatedFieldsAsMap()
                .containsKey('Enable_Recovery__c') ||
            settings.Enable_Recovery__c == true;
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
        public Boolean effectiveRecoveryEnabled;
        @AuraEnabled
        public Integer effectiveMaxThreads;
        @AuraEnabled
        public Integer effectiveRecoveryBatchSize;
        @AuraEnabled
        public Integer effectiveRecoveryLimitThresholdPct;
        @AuraEnabled
        public Integer effectiveRecoveryThresholdMinutes;
    }

    public class SettingsRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id setupOwnerId;
        @AuraEnabled
        public String scope;
        @AuraEnabled
        public Boolean recoveryEnabled;
        @AuraEnabled
        public Decimal maxThreads;
        @AuraEnabled
        public Decimal recoveryBatchSize;
        @AuraEnabled
        public Decimal recoveryLimitThresholdPct;
        @AuraEnabled
        public Decimal recoveryThresholdMinutes;
        @AuraEnabled
        public Boolean hasRecord;

        SettingsRow(
            Thread_Settings__c settings,
            Id setupOwnerId,
            String scope
        ) {
            this.id = settings == null ? null : settings.Id;
            this.setupOwnerId = setupOwnerId;
            this.scope = scope;
            this.recoveryEnabled = recoveryEnabled(settings);
            this.maxThreads = settings == null ? null : settings.Max_Threads__c;
            this.recoveryBatchSize = settings == null
                ? null
                : settings.Recovery_Batch_Size__c;
            this.recoveryLimitThresholdPct = settings == null
                ? null
                : settings.Recovery_Limit_Threshold_Pct__c;
            this.recoveryThresholdMinutes = settings == null
                ? null
                : settings.Recovery_Threshold_Minutes__c;
            this.hasRecord = settings != null;
        }
    }

    public class UserSettingRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id setupOwnerId;
        @AuraEnabled
        public Boolean recoveryEnabled;
        @AuraEnabled
        public Decimal maxThreads;
        @AuraEnabled
        public Decimal recoveryBatchSize;
        @AuraEnabled
        public Decimal recoveryLimitThresholdPct;
        @AuraEnabled
        public Decimal recoveryThresholdMinutes;
        @AuraEnabled
        public Boolean hasRecord;
        @AuraEnabled
        public UserOption user;

        UserSettingRow(Thread_Settings__c settings, User userRecord) {
            this.id = settings.Id;
            this.setupOwnerId = settings.SetupOwnerId;
            this.recoveryEnabled = recoveryEnabled(settings);
            this.maxThreads = settings.Max_Threads__c;
            this.recoveryBatchSize = settings.Recovery_Batch_Size__c;
            this.recoveryLimitThresholdPct = settings.Recovery_Limit_Threshold_Pct__c;
            this.recoveryThresholdMinutes = settings.Recovery_Threshold_Minutes__c;
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
