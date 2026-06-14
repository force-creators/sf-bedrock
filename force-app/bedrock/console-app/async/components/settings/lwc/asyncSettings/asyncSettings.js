import { LightningElement } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import deleteUserSettings from '@salesforce/apex/AsyncSettingsController.deleteUserSettings';
import getSettings from '@salesforce/apex/AsyncSettingsController.getSettings';
import saveSettings from '@salesforce/apex/AsyncSettingsController.saveSettings';
import searchUsers from '@salesforce/apex/AsyncSettingsController.searchUsers';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const USER_SEARCH_DELAY_MS = 250;

export default class AsyncSettings extends LightningElement {
    settings;
    organizationMaxThreads;
    userOverrideRows = [];
    newUserMaxThreads;
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

    get organizationRecordLabel() {
        return this.settings?.organization?.hasRecord ? 'Custom setting exists' : 'Using framework default';
    }

    get organizationMaxThreadsDisplay() {
        return this.organizationMaxThreads || 'Default';
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
        this.organizationMaxThreads = this.toInputValue(this.settings?.organization?.maxThreads);
        this.isEditingOrganization = false;
    }

    handleOrganizationMaxThreadsChange(event) {
        this.organizationMaxThreads = event.target.value;
    }

    handleOverrideMaxThreadsChange(event) {
        const userId = event.target.dataset.userId;
        const value = event.target.value;
        this.userOverrideRows = this.userOverrideRows.map((row) => {
            if (row.userId !== userId) {
                return row;
            }

            return {
                ...row,
                draftMaxThreads: value
            };
        });
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

            return {
                ...row,
                draftMaxThreads: this.toInputValue(row.maxThreads),
                isEditing: false
            };
        });
    }

    handleNewUserMaxThreadsChange(event) {
        this.newUserMaxThreads = event.target.value;
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
        this.saveSetting('Organization', null, this.organizationMaxThreads, 'Global settings saved');
    }

    handleCreateUserOverride() {
        this.isCreatingUserOverride = true;
        this.selectedUser = this.settings?.currentUser;
        this.userSearchTerm = this.selectedUserLabel;
        this.userOptions = [];
        this.newUserMaxThreads = null;
    }

    handleCancelCreateUserOverride() {
        this.isCreatingUserOverride = false;
        this.selectedUser = this.settings?.selectedUser;
        this.userSearchTerm = this.selectedUserLabel;
        this.userOptions = [];
        this.newUserMaxThreads = null;
    }

    handleSaveUserOverride(event) {
        const userId = event.currentTarget.dataset.userId;
        const row = this.userOverrideRows.find((overrideRow) => overrideRow.userId === userId);

        if (row) {
            this.saveSetting('User', userId, row.draftMaxThreads, 'User settings saved');
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
            message: `Delete async settings for ${row.userLabel}? This user will inherit the global setting.`,
            theme: 'error',
            variant: 'header'
        });

        if (!confirmed) {
            return;
        }

        this.deleteUserOverride(userId);
    }

    handleSaveNewUserOverride() {
        this.saveSetting('User', this.selectedUser.id, this.newUserMaxThreads, 'User settings saved');
    }

    async loadSettings(userId) {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            this.settings = await getSettings({ userId });
            this.selectedUser = this.settings.selectedUser;
            this.organizationMaxThreads = this.toInputValue(this.settings.organization?.maxThreads);
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

    async saveSetting(scope, userId, maxThreads, title) {
        this.isSaving = true;
        this.errorMessage = undefined;

        try {
            this.settings = await saveSettings({
                scope,
                userId,
                maxThreads: this.toNumber(maxThreads)
            });
            this.selectedUser = this.settings.selectedUser;
            this.organizationMaxThreads = this.toInputValue(this.settings.organization?.maxThreads);
            this.userOverrideRows = this.toUserOverrideRows(this.settings.userOverrides);
            this.userSearchTerm = this.selectedUserLabel;
            this.isCreatingUserOverride = false;
            this.newUserMaxThreads = null;
            this.isEditingOrganization = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title,
                    message: 'Async thread settings were updated.',
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
            this.organizationMaxThreads = this.toInputValue(this.settings.organization?.maxThreads);
            this.userOverrideRows = this.toUserOverrideRows(this.settings.userOverrides);
            this.userSearchTerm = this.selectedUserLabel;
            this.isCreatingUserOverride = false;
            this.newUserMaxThreads = null;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'User settings deleted',
                    message: 'The user now inherits global async thread settings.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.isSaving = false;
        }
    }

    toUserOverrideRows(rows = []) {
        return rows.map((row) => ({
            id: row.id,
            userId: row.user.id,
            userLabel: row.user.label,
            username: row.user.username,
            maxThreads: row.maxThreads,
            maxThreadsDisplay: this.toDisplayValue(row.maxThreads),
            draftMaxThreads: this.toInputValue(row.maxThreads),
            isEditing: false
        }));
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

        return error?.body?.message || error?.message || 'Unable to load async settings.';
    }
}
