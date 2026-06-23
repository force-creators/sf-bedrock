import { LightningElement } from "lwc";
import LightningConfirm from "lightning/confirm";
import deleteUserSettings from "@salesforce/apex/AsyncSettingsController.deleteUserSettings";
import getSettings from "@salesforce/apex/AsyncSettingsController.getSettings";
import saveSettings from "@salesforce/apex/AsyncSettingsController.saveSettings";
import searchUsers from "@salesforce/apex/AsyncSettingsController.searchUsers";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

const USER_SEARCH_DELAY_MS = 250;

export default class AsyncSettings extends LightningElement {
    settings;
    organizationArchiveCleanupEnabled = false;
    organizationArchiveThresholdHours;
    organizationMaxArchiveAgeDays;
    organizationMaxThreads;
    userOverrideRows = [];
    newUserArchiveCleanupEnabled = false;
    newUserArchiveThresholdHours;
    newUserMaxArchiveAgeDays;
    newUserMaxThreads;
    selectedUser;
    userSearchTerm = "";
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

    get effectiveArchiveThresholdLabel() {
        const threshold = this.settings?.effectiveArchiveThresholdHours;
        return `Archive after: ${threshold === null || threshold === undefined ? 24 : threshold} hours`;
    }

    get effectiveMaxArchiveAgeLabel() {
        const maxArchiveAge = this.settings?.effectiveMaxArchiveAgeDays;
        return `Clean archive after: ${maxArchiveAge === null || maxArchiveAge === undefined ? 30 : maxArchiveAge} days`;
    }

    get archiveCleanupStatusLabel() {
        return this.settings?.effectiveArchiveCleanupEnabled
            ? "Archive cleanup enabled"
            : "Archive cleanup disabled";
    }

    get organizationRecordLabel() {
        return this.settings?.organization?.hasRecord
            ? "Custom setting exists"
            : "Using framework default";
    }

    get organizationMaxThreadsDisplay() {
        return this.organizationMaxThreads || "Default";
    }

    get organizationArchiveThresholdDisplay() {
        return this.toDisplayValue(this.organizationArchiveThresholdHours);
    }

    get organizationMaxArchiveAgeDisplay() {
        return this.toDisplayValue(this.organizationMaxArchiveAgeDays);
    }

    get organizationArchiveCleanupDisplay() {
        return this.organizationArchiveCleanupEnabled ? "Enabled" : "Disabled";
    }

    get userOverrideCountLabel() {
        const count = this.userOverrideRows.length;
        return `${count} ${count === 1 ? "config" : "configs"}`;
    }

    get selectedUserLabel() {
        if (!this.selectedUser) {
            return "";
        }

        return `${this.selectedUser.label} (${this.selectedUser.username})`;
    }

    get newOverrideHeading() {
        return this.selectedUser?.label || "Choose a User";
    }

    get newOverrideSubheading() {
        return this.selectedUser?.username || "Search active users";
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
        this.organizationArchiveCleanupEnabled =
            this.settings?.organization?.archiveCleanupEnabled || false;
        this.organizationArchiveThresholdHours = this.toInputValue(
            this.settings?.organization?.archiveThresholdHours
        );
        this.organizationMaxArchiveAgeDays = this.toInputValue(
            this.settings?.organization?.maxArchiveAgeDays
        );
        this.organizationMaxThreads = this.toInputValue(
            this.settings?.organization?.maxThreads
        );
        this.isEditingOrganization = false;
    }

    handleOrganizationMaxThreadsChange(event) {
        this.organizationMaxThreads = event.target.value;
    }

    handleOrganizationArchiveThresholdChange(event) {
        this.organizationArchiveThresholdHours = event.target.value;
    }

    handleOrganizationMaxArchiveAgeChange(event) {
        this.organizationMaxArchiveAgeDays = event.target.value;
    }

    handleOrganizationArchiveCleanupChange(event) {
        this.organizationArchiveCleanupEnabled = event.target.checked;
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

    handleOverrideArchiveThresholdChange(event) {
        const userId = event.target.dataset.userId;
        const value = event.target.value;
        this.userOverrideRows = this.userOverrideRows.map((row) => {
            if (row.userId !== userId) {
                return row;
            }

            return {
                ...row,
                draftArchiveThresholdHours: value
            };
        });
    }

    handleOverrideMaxArchiveAgeChange(event) {
        const userId = event.target.dataset.userId;
        const value = event.target.value;
        this.userOverrideRows = this.userOverrideRows.map((row) => {
            if (row.userId !== userId) {
                return row;
            }

            return {
                ...row,
                draftMaxArchiveAgeDays: value
            };
        });
    }

    handleOverrideArchiveCleanupChange(event) {
        const userId = event.target.dataset.userId;
        const checked = event.target.checked;
        this.userOverrideRows = this.userOverrideRows.map((row) => {
            if (row.userId !== userId) {
                return row;
            }

            return {
                ...row,
                draftArchiveCleanupEnabled: checked
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
                draftArchiveCleanupEnabled: row.archiveCleanupEnabled,
                draftArchiveThresholdHours: this.toInputValue(
                    row.archiveThresholdHours
                ),
                draftMaxArchiveAgeDays: this.toInputValue(
                    row.maxArchiveAgeDays
                ),
                draftMaxThreads: this.toInputValue(row.maxThreads),
                isEditing: false
            };
        });
    }

    handleNewUserMaxThreadsChange(event) {
        this.newUserMaxThreads = event.target.value;
    }

    handleNewUserArchiveThresholdChange(event) {
        this.newUserArchiveThresholdHours = event.target.value;
    }

    handleNewUserMaxArchiveAgeChange(event) {
        this.newUserMaxArchiveAgeDays = event.target.value;
    }

    handleNewUserArchiveCleanupChange(event) {
        this.newUserArchiveCleanupEnabled = event.target.checked;
    }

    handleUserSearchFocus() {
        if (this.userOptions.length === 0) {
            this.searchForUsers(this.userSearchTerm);
        }
    }

    handleUserSearchChange(event) {
        this.userSearchTerm = event.target.value;
        this.clearUserSearchTimer();
        // Debounce user lookup requests while typing.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.userSearchTimer = setTimeout(() => {
            this.searchForUsers(this.userSearchTerm);
        }, USER_SEARCH_DELAY_MS);
    }

    handleUserSelect(event) {
        const userId = event.currentTarget.dataset.userId;
        const userOption = this.userOptions.find(
            (option) => option.id === userId
        );

        if (!userOption) {
            return;
        }

        this.selectedUser = userOption;
        this.userSearchTerm = this.selectedUserLabel;
        this.userOptions = [];
    }

    handleSaveOrganization() {
        this.saveSetting(
            "Organization",
            null,
            this.organizationMaxThreads,
            this.organizationArchiveThresholdHours,
            this.organizationMaxArchiveAgeDays,
            this.organizationArchiveCleanupEnabled,
            "Global settings saved"
        );
    }

    handleCreateUserOverride() {
        this.isCreatingUserOverride = true;
        this.selectedUser = this.settings?.currentUser;
        this.userSearchTerm = this.selectedUserLabel;
        this.userOptions = [];
        this.newUserArchiveCleanupEnabled = false;
        this.newUserArchiveThresholdHours = null;
        this.newUserMaxArchiveAgeDays = null;
        this.newUserMaxThreads = null;
    }

    handleCancelCreateUserOverride() {
        this.isCreatingUserOverride = false;
        this.selectedUser = this.settings?.selectedUser;
        this.userSearchTerm = this.selectedUserLabel;
        this.userOptions = [];
        this.newUserArchiveCleanupEnabled = false;
        this.newUserArchiveThresholdHours = null;
        this.newUserMaxArchiveAgeDays = null;
        this.newUserMaxThreads = null;
    }

    handleSaveUserOverride(event) {
        const userId = event.currentTarget.dataset.userId;
        const row = this.userOverrideRows.find(
            (overrideRow) => overrideRow.userId === userId
        );

        if (row) {
            this.saveSetting(
                "User",
                userId,
                row.draftMaxThreads,
                row.draftArchiveThresholdHours,
                row.draftMaxArchiveAgeDays,
                row.draftArchiveCleanupEnabled,
                "User settings saved"
            );
        }
    }

    async handleDeleteUserOverride(event) {
        const userId = event.currentTarget.dataset.userId;
        const row = this.userOverrideRows.find(
            (overrideRow) => overrideRow.userId === userId
        );

        if (!row) {
            return;
        }

        const confirmed = await LightningConfirm.open({
            label: "Delete user settings",
            message: `Delete async settings for ${row.userLabel}? This user will inherit the global setting.`,
            theme: "error",
            variant: "header"
        });

        if (!confirmed) {
            return;
        }

        this.deleteUserOverride(userId);
    }

    handleSaveNewUserOverride() {
        this.saveSetting(
            "User",
            this.selectedUser.id,
            this.newUserMaxThreads,
            this.newUserArchiveThresholdHours,
            this.newUserMaxArchiveAgeDays,
            this.newUserArchiveCleanupEnabled,
            "User settings saved"
        );
    }

    async loadSettings(userId) {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            this.settings = await getSettings({ userId });
            this.selectedUser = this.settings.selectedUser;
            this.organizationArchiveCleanupEnabled =
                this.settings.organization?.archiveCleanupEnabled || false;
            this.organizationArchiveThresholdHours = this.toInputValue(
                this.settings.organization?.archiveThresholdHours
            );
            this.organizationMaxArchiveAgeDays = this.toInputValue(
                this.settings.organization?.maxArchiveAgeDays
            );
            this.organizationMaxThreads = this.toInputValue(
                this.settings.organization?.maxThreads
            );
            this.userOverrideRows = this.toUserOverrideRows(
                this.settings.userOverrides
            );
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

    async saveSetting(
        scope,
        userId,
        maxThreads,
        archiveThresholdHours,
        maxArchiveAgeDays,
        archiveCleanupEnabled,
        title
    ) {
        this.isSaving = true;
        this.errorMessage = undefined;

        try {
            this.settings = await saveSettings({
                scope,
                userId,
                maxThreads: this.toNumber(maxThreads),
                archiveThresholdHours: this.toNumber(archiveThresholdHours),
                maxArchiveAgeDays: this.toNumber(maxArchiveAgeDays),
                archiveCleanupEnabled
            });
            this.selectedUser = this.settings.selectedUser;
            this.organizationArchiveCleanupEnabled =
                this.settings.organization?.archiveCleanupEnabled || false;
            this.organizationArchiveThresholdHours = this.toInputValue(
                this.settings.organization?.archiveThresholdHours
            );
            this.organizationMaxArchiveAgeDays = this.toInputValue(
                this.settings.organization?.maxArchiveAgeDays
            );
            this.organizationMaxThreads = this.toInputValue(
                this.settings.organization?.maxThreads
            );
            this.userOverrideRows = this.toUserOverrideRows(
                this.settings.userOverrides
            );
            this.userSearchTerm = this.selectedUserLabel;
            this.isCreatingUserOverride = false;
            this.newUserArchiveCleanupEnabled = false;
            this.newUserArchiveThresholdHours = null;
            this.newUserMaxArchiveAgeDays = null;
            this.newUserMaxThreads = null;
            this.isEditingOrganization = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title,
                    message: "Async thread settings were updated.",
                    variant: "success"
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
            this.organizationArchiveCleanupEnabled =
                this.settings.organization?.archiveCleanupEnabled || false;
            this.organizationArchiveThresholdHours = this.toInputValue(
                this.settings.organization?.archiveThresholdHours
            );
            this.organizationMaxArchiveAgeDays = this.toInputValue(
                this.settings.organization?.maxArchiveAgeDays
            );
            this.organizationMaxThreads = this.toInputValue(
                this.settings.organization?.maxThreads
            );
            this.userOverrideRows = this.toUserOverrideRows(
                this.settings.userOverrides
            );
            this.userSearchTerm = this.selectedUserLabel;
            this.isCreatingUserOverride = false;
            this.newUserArchiveCleanupEnabled = false;
            this.newUserArchiveThresholdHours = null;
            this.newUserMaxArchiveAgeDays = null;
            this.newUserMaxThreads = null;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "User settings deleted",
                    message:
                        "The user now inherits global async thread settings.",
                    variant: "success"
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
            archiveCleanupEnabled: row.archiveCleanupEnabled,
            archiveCleanupDisplay: row.archiveCleanupEnabled
                ? "Enabled"
                : "Disabled",
            archiveThresholdHours: row.archiveThresholdHours,
            archiveThresholdDisplay: this.toDisplayValue(
                row.archiveThresholdHours
            ),
            maxArchiveAgeDays: row.maxArchiveAgeDays,
            maxArchiveAgeDisplay: this.toDisplayValue(row.maxArchiveAgeDays),
            draftArchiveCleanupEnabled: row.archiveCleanupEnabled,
            draftArchiveThresholdHours: this.toInputValue(
                row.archiveThresholdHours
            ),
            draftMaxArchiveAgeDays: this.toInputValue(row.maxArchiveAgeDays),
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
        return value === null || value === undefined || value === ""
            ? "Default"
            : String(value);
    }

    toNumber(value) {
        if (value === null || value === undefined || value === "") {
            return null;
        }

        return Number(value);
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(", ");
        }

        return (
            error?.body?.message ||
            error?.message ||
            "Unable to load async settings."
        );
    }
}
