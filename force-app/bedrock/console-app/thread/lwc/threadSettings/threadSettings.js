import { LightningElement } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import deleteUserSettings from '@salesforce/apex/ThreadSettingsController.deleteUserSettings';
import getSettings from '@salesforce/apex/ThreadSettingsController.getSettings';
import saveSettings from '@salesforce/apex/ThreadSettingsController.saveSettings';
import searchUsers from '@salesforce/apex/ThreadSettingsController.searchUsers';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const USER_SEARCH_DELAY_MS = 250;

export default class ThreadSettings extends LightningElement {
    settings;
    organizationRecoveryEnabled = true;
    organizationMaxThreads;
    organizationRecoveryBatchSize;
    organizationRecoveryLimitThresholdPct;
    organizationRecoveryThresholdMinutes;
    userOverrideRows = [];
    newUserRecoveryEnabled = true;
    newUserMaxThreads;
    newUserRecoveryBatchSize;
    newUserRecoveryLimitThresholdPct;
    newUserRecoveryThresholdMinutes;
    selectedUser;
    userSearchTerm = '';
    userOptions = [];
    isCreatingUserOverride = false;
    isEditingOrganization = false;
    isLoading = false;
    isSaving = false;
    errorMessage;
    userSearchTimer;

    connectedCallback() {
        this.loadSettings();
    }

    disconnectedCallback() {
        this.clearUserSearchTimer();
    }

    get hasSettings() {
        return Boolean(this.settings);
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get hasUserOptions() {
        return this.userOptions.length > 0;
    }

    get hasUserOverrideRows() {
        return this.userOverrideRows.length > 0;
    }

    get effectiveMaxThreadsLabel() {
        return `Effective max threads: ${this.settings?.effectiveMaxThreads || 1}`;
    }

    get effectiveRecoveryThresholdLabel() {
        return `Recover after: ${this.settings?.effectiveRecoveryThresholdMinutes || 10} minutes`;
    }

    get effectiveRecoveryBatchSizeLabel() {
        return `Recovery batch: ${this.settings?.effectiveRecoveryBatchSize || 10}`;
    }

    get effectiveRecoveryLimitLabel() {
        return `Limit threshold: ${this.settings?.effectiveRecoveryLimitThresholdPct || 90}%`;
    }

    get recoveryStatusLabel() {
        return this.settings?.effectiveRecoveryEnabled ? 'Recovery enabled' : 'Recovery disabled';
    }

    get organizationRecordLabel() {
        return this.settings?.organization?.hasRecord ? 'Custom setting exists' : 'Using framework default';
    }

    get organizationMaxThreadsDisplay() {
        return this.toDisplayValue(this.organizationMaxThreads);
    }

    get organizationRecoveryThresholdDisplay() {
        return this.toDisplayValue(this.organizationRecoveryThresholdMinutes);
    }

    get organizationRecoveryBatchSizeDisplay() {
        return this.toDisplayValue(this.organizationRecoveryBatchSize);
    }

    get organizationRecoveryLimitDisplay() {
        return this.toDisplayValue(this.organizationRecoveryLimitThresholdPct);
    }

    get organizationRecoveryDisplay() {
        return this.organizationRecoveryEnabled ? 'Enabled' : 'Disabled';
    }

    get userOverrideCountLabel() {
        const count = this.userOverrideRows.length;
        return `${count} ${count === 1 ? 'config' : 'configs'}`;
    }

    get selectedUserLabel() {
        if (!this.selectedUser) {
            return '';
        }

        return `${this.selectedUser.label} (${this.selectedUser.username})`;
    }

    get newOverrideHeading() {
        return this.selectedUser?.label || 'Choose a User';
    }

    get newOverrideSubheading() {
        return this.selectedUser?.username || 'Search active users';
    }

    get isNewUserSaveDisabled() {
        return this.isSaving || !this.selectedUser?.id;
    }

    handleRefresh() {
        this.isEditingOrganization = false;
        this.loadSettings(this.selectedUser?.id);
    }

    handleEditOrganization() {
        this.isEditingOrganization = true;
    }

    handleCancelOrganizationEdit() {
        this.applyOrganizationSettings(this.settings);
        this.isEditingOrganization = false;
    }

    handleOrganizationMaxThreadsChange(event) {
        this.organizationMaxThreads = event.target.value;
    }

    handleOrganizationRecoveryThresholdChange(event) {
        this.organizationRecoveryThresholdMinutes = event.target.value;
    }

    handleOrganizationRecoveryBatchSizeChange(event) {
        this.organizationRecoveryBatchSize = event.target.value;
    }

    handleOrganizationRecoveryLimitChange(event) {
        this.organizationRecoveryLimitThresholdPct = event.target.value;
    }

    handleOrganizationRecoveryEnabledChange(event) {
        this.organizationRecoveryEnabled = event.target.checked;
    }

    handleOverrideMaxThreadsChange(event) {
        this.updateOverrideDraft(event.target.dataset.userId, { draftMaxThreads: event.target.value });
    }

    handleOverrideRecoveryThresholdChange(event) {
        this.updateOverrideDraft(event.target.dataset.userId, { draftRecoveryThresholdMinutes: event.target.value });
    }

    handleOverrideRecoveryBatchSizeChange(event) {
        this.updateOverrideDraft(event.target.dataset.userId, { draftRecoveryBatchSize: event.target.value });
    }

    handleOverrideRecoveryLimitChange(event) {
        this.updateOverrideDraft(event.target.dataset.userId, { draftRecoveryLimitThresholdPct: event.target.value });
    }

    handleOverrideRecoveryEnabledChange(event) {
        this.updateOverrideDraft(event.target.dataset.userId, { draftRecoveryEnabled: event.target.checked });
    }

    handleEditUserOverride(event) {
        const userId = event.currentTarget.dataset.userId;
        this.userOverrideRows = this.userOverrideRows.map((row) => ({
            ...row,
            isEditing: row.userId === userId
        }));
    }

    handleCancelUserOverrideEdit(event) {
        const userId = event.currentTarget.dataset.userId;
        this.userOverrideRows = this.userOverrideRows.map((row) => {
            if (row.userId !== userId) {
                return row;
            }

            return this.toUserOverrideRow(row.source);
        });
    }

    handleNewUserMaxThreadsChange(event) {
        this.newUserMaxThreads = event.target.value;
    }

    handleNewUserRecoveryThresholdChange(event) {
        this.newUserRecoveryThresholdMinutes = event.target.value;
    }

    handleNewUserRecoveryBatchSizeChange(event) {
        this.newUserRecoveryBatchSize = event.target.value;
    }

    handleNewUserRecoveryLimitChange(event) {
        this.newUserRecoveryLimitThresholdPct = event.target.value;
    }

    handleNewUserRecoveryEnabledChange(event) {
        this.newUserRecoveryEnabled = event.target.checked;
    }

    handleUserSearchFocus() {
        if (this.userOptions.length === 0) {
            this.searchForUsers(this.userSearchTerm);
        }
    }

    handleUserSearchChange(event) {
        this.userSearchTerm = event.target.value;
        this.clearUserSearchTimer();
        this.userSearchTimer = setTimeout(() => {
            this.searchForUsers(this.userSearchTerm);
        }, USER_SEARCH_DELAY_MS);
    }

    handleUserSelect(event) {
        const userId = event.currentTarget.dataset.userId;
        const userOption = this.userOptions.find((option) => option.id === userId);

        if (!userOption) {
            return;
        }

        this.selectedUser = userOption;
        this.userSearchTerm = this.selectedUserLabel;
        this.userOptions = [];
    }

    handleSaveOrganization() {
        this.saveSetting(
            'Organization',
            null,
            this.organizationMaxThreads,
            this.organizationRecoveryThresholdMinutes,
            this.organizationRecoveryBatchSize,
            this.organizationRecoveryLimitThresholdPct,
            this.organizationRecoveryEnabled,
            'Global settings saved'
        );
    }

    handleCreateUserOverride() {
        this.isCreatingUserOverride = true;
        this.selectedUser = this.settings?.currentUser;
        this.userSearchTerm = this.selectedUserLabel;
        this.userOptions = [];
        this.newUserRecoveryEnabled = true;
        this.newUserMaxThreads = null;
        this.newUserRecoveryBatchSize = null;
        this.newUserRecoveryLimitThresholdPct = null;
        this.newUserRecoveryThresholdMinutes = null;
    }

    handleCancelCreateUserOverride() {
        this.isCreatingUserOverride = false;
        this.selectedUser = this.settings?.selectedUser;
        this.userSearchTerm = this.selectedUserLabel;
        this.userOptions = [];
        this.newUserRecoveryEnabled = true;
        this.newUserMaxThreads = null;
        this.newUserRecoveryBatchSize = null;
        this.newUserRecoveryLimitThresholdPct = null;
        this.newUserRecoveryThresholdMinutes = null;
    }

    handleSaveUserOverride(event) {
        const userId = event.currentTarget.dataset.userId;
        const row = this.userOverrideRows.find((overrideRow) => overrideRow.userId === userId);

        if (row) {
            this.saveSetting(
                'User',
                userId,
                row.draftMaxThreads,
                row.draftRecoveryThresholdMinutes,
                row.draftRecoveryBatchSize,
                row.draftRecoveryLimitThresholdPct,
                row.draftRecoveryEnabled,
                'User settings saved'
            );
        }
    }

    async handleDeleteUserOverride(event) {
        const userId = event.currentTarget.dataset.userId;
        const row = this.userOverrideRows.find((overrideRow) => overrideRow.userId === userId);

        if (!row) {
            return;
        }

        const confirmed = await LightningConfirm.open({
            label: 'Delete user settings',
            message: `Delete thread settings for ${row.userLabel}? This user will inherit the global setting.`,
            theme: 'error',
            variant: 'header'
        });

        if (!confirmed) {
            return;
        }

        this.deleteUserOverride(userId);
    }

    handleSaveNewUserOverride() {
        this.saveSetting(
            'User',
            this.selectedUser.id,
            this.newUserMaxThreads,
            this.newUserRecoveryThresholdMinutes,
            this.newUserRecoveryBatchSize,
            this.newUserRecoveryLimitThresholdPct,
            this.newUserRecoveryEnabled,
            'User settings saved'
        );
    }

    async loadSettings(userId) {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            this.settings = await getSettings({ userId });
            this.selectedUser = this.settings.selectedUser;
            this.applyOrganizationSettings(this.settings);
            this.userOverrideRows = this.toUserOverrideRows(this.settings.userOverrides);
            this.userSearchTerm = this.selectedUserLabel;
            this.isEditingOrganization = false;
        } catch (error) {
            this.settings = undefined;
            this.userOverrideRows = [];
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.isLoading = false;
        }
    }

    async searchForUsers(searchTerm) {
        try {
            this.userOptions = await searchUsers({ searchTerm });
        } catch (error) {
            this.userOptions = [];
            this.errorMessage = this.reduceErrors(error);
        }
    }

    async saveSetting(scope, userId, maxThreads, recoveryThresholdMinutes, recoveryBatchSize, recoveryLimitThresholdPct, recoveryEnabled, title) {
        this.isSaving = true;
        this.errorMessage = undefined;

        try {
            this.settings = await saveSettings({
                scope,
                userId,
                maxThreads: this.toNumber(maxThreads),
                recoveryThresholdMinutes: this.toNumber(recoveryThresholdMinutes),
                recoveryBatchSize: this.toNumber(recoveryBatchSize),
                recoveryLimitThresholdPct: this.toNumber(recoveryLimitThresholdPct),
                recoveryEnabled
            });
            this.selectedUser = this.settings.selectedUser;
            this.applyOrganizationSettings(this.settings);
            this.userOverrideRows = this.toUserOverrideRows(this.settings.userOverrides);
            this.userSearchTerm = this.selectedUserLabel;
            this.isCreatingUserOverride = false;
            this.newUserRecoveryEnabled = true;
            this.newUserMaxThreads = null;
            this.newUserRecoveryBatchSize = null;
            this.newUserRecoveryLimitThresholdPct = null;
            this.newUserRecoveryThresholdMinutes = null;
            this.isEditingOrganization = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title,
                    message: 'Thread settings were updated.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.isSaving = false;
        }
    }

    async deleteUserOverride(userId) {
        this.isSaving = true;
        this.errorMessage = undefined;

        try {
            this.settings = await deleteUserSettings({ userId });
            this.selectedUser = this.settings.selectedUser;
            this.applyOrganizationSettings(this.settings);
            this.userOverrideRows = this.toUserOverrideRows(this.settings.userOverrides);
            this.userSearchTerm = this.selectedUserLabel;
            this.isCreatingUserOverride = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'User settings deleted',
                    message: 'The user now inherits global thread settings.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.isSaving = false;
        }
    }

    applyOrganizationSettings(settings) {
        this.organizationRecoveryEnabled = settings?.organization?.recoveryEnabled !== false;
        this.organizationMaxThreads = this.toInputValue(settings?.organization?.maxThreads);
        this.organizationRecoveryBatchSize = this.toInputValue(settings?.organization?.recoveryBatchSize);
        this.organizationRecoveryLimitThresholdPct = this.toInputValue(settings?.organization?.recoveryLimitThresholdPct);
        this.organizationRecoveryThresholdMinutes = this.toInputValue(settings?.organization?.recoveryThresholdMinutes);
    }

    updateOverrideDraft(userId, changes) {
        this.userOverrideRows = this.userOverrideRows.map((row) => {
            if (row.userId !== userId) {
                return row;
            }

            return {
                ...row,
                ...changes
            };
        });
    }

    toUserOverrideRows(rows = []) {
        return rows.map((row) => this.toUserOverrideRow(row));
    }

    toUserOverrideRow(row) {
        return {
            id: row.id,
            source: row,
            recoveryEnabled: row.recoveryEnabled,
            recoveryDisplay: row.recoveryEnabled ? 'Enabled' : 'Disabled',
            recoveryThresholdMinutes: row.recoveryThresholdMinutes,
            recoveryThresholdDisplay: this.toDisplayValue(row.recoveryThresholdMinutes),
            recoveryBatchSize: row.recoveryBatchSize,
            recoveryBatchSizeDisplay: this.toDisplayValue(row.recoveryBatchSize),
            recoveryLimitThresholdPct: row.recoveryLimitThresholdPct,
            recoveryLimitDisplay: this.toDisplayValue(row.recoveryLimitThresholdPct),
            draftRecoveryEnabled: row.recoveryEnabled,
            draftRecoveryThresholdMinutes: this.toInputValue(row.recoveryThresholdMinutes),
            draftRecoveryBatchSize: this.toInputValue(row.recoveryBatchSize),
            draftRecoveryLimitThresholdPct: this.toInputValue(row.recoveryLimitThresholdPct),
            userId: row.user.id,
            userLabel: row.user.label,
            username: row.user.username,
            maxThreads: row.maxThreads,
            maxThreadsDisplay: this.toDisplayValue(row.maxThreads),
            draftMaxThreads: this.toInputValue(row.maxThreads),
            isEditing: false
        };
    }

    clearUserSearchTimer() {
        if (this.userSearchTimer) {
            clearTimeout(this.userSearchTimer);
            this.userSearchTimer = undefined;
        }
    }

    toInputValue(value) {
        return value === null || value === undefined ? null : String(value);
    }

    toDisplayValue(value) {
        return value === null || value === undefined || value === '' ? 'Default' : String(value);
    }

    toNumber(value) {
        if (value === null || value === undefined || value === '') {
            return null;
        }

        return Number(value);
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load thread settings.';
    }
}
