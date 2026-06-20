import { LightningElement } from 'lwc';
import createEndpoint from '@salesforce/apex/RestConsoleController.createEndpoint';
import getState from '@salesforce/apex/RestConsoleController.getState';
import saveSettings from '@salesforce/apex/RestConsoleController.saveSettings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const REFRESH_INTERVAL_MS = 15000;

const METRIC_DEFINITIONS = [
    { id: 'routeCount', label: 'Routes', className: 'metric metric-routes' },
    { id: 'activeRouteCount', label: 'Active', className: 'metric metric-active' },
    { id: 'inactiveRouteCount', label: 'Inactive', className: 'metric metric-inactive' },
    { id: 'versionedRouteCount', label: 'Versions', className: 'metric metric-versions' }
];

export default class RestLayout extends LightningElement {
    state;
    routes = [];
    restClassOptions = [];
    metrics = this.emptyMetrics();
    settings = {};
    isLoading = false;
    isSavingSettings = false;
    isEditingSettings = false;
    isCreatingEndpoint = false;
    isEndpointModalOpen = false;
    errorMessage;
    lastRefreshedAt;
    refreshTimer;
    expandedEndpointKeys = new Set();
    expandedRouteKeys = new Set();
    editingEndpointKey;
    versionRouteKey;

    settingsDraft = {
        unknownRouteStatusCode: undefined,
        inactiveRouteStatusCode: undefined,
        unsupportedMethodStatusCode: undefined,
        accessDeniedStatusCode: undefined,
        exposeErrorDetails: false
    };

    endpointDraft = {
        developerName: '',
        label: '',
        route: '',
        version: 1,
        apexClass: '',
        active: true,
        defaultVersion: false
    };

    connectedCallback() {
        this.loadState();
        this.startRefresh();
    }

    disconnectedCallback() {
        this.stopRefresh();
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get hasRoutes() {
        return this.routes.length > 0;
    }

    get hasRestClassOptions() {
        return this.restClassOptions.length > 0;
    }

    get routeCountLabel() {
        const count = this.routes.length;
        return `${count} ${count === 1 ? 'route' : 'routes'}`;
    }

    get settingsRecordLabel() {
        return this.settings?.hasRecord ? 'Custom setting exists' : 'Using framework defaults';
    }

    get errorDetailsLabel() {
        return this.settingsDraft.exposeErrorDetails ? 'Exposed' : 'Hidden';
    }

    get unknownRouteStatusDisplay() {
        return this.toDisplayValue(this.settingsDraft.unknownRouteStatusCode, this.settings?.effectiveUnknownRouteStatusCode);
    }

    get inactiveRouteStatusDisplay() {
        return this.toDisplayValue(this.settingsDraft.inactiveRouteStatusCode, this.settings?.effectiveInactiveRouteStatusCode);
    }

    get unsupportedMethodStatusDisplay() {
        return this.toDisplayValue(this.settingsDraft.unsupportedMethodStatusCode, this.settings?.effectiveUnsupportedMethodStatusCode);
    }

    get accessDeniedStatusDisplay() {
        return this.toDisplayValue(this.settingsDraft.accessDeniedStatusCode, this.settings?.effectiveAccessDeniedStatusCode);
    }

    get lastRefreshedLabel() {
        if (!this.lastRefreshedAt) {
            return 'Last refreshed: Not yet';
        }

        return `Last refreshed: ${this.lastRefreshedAt.toLocaleTimeString()}`;
    }

    get settingsSaveDisabled() {
        return this.isSavingSettings || this.isLoading;
    }

    get endpointCreateDisabled() {
        return this.isCreatingEndpoint || !this.endpointDraft.route || !this.endpointDraft.version || !this.endpointDraft.apexClass;
    }

    get isEditingEndpoint() {
        return Boolean(this.editingEndpointKey);
    }

    get isCreatingVersion() {
        return Boolean(this.versionRouteKey);
    }

    get endpointModalTitle() {
        if (this.isEditingEndpoint) return 'Edit Endpoint';
        return this.isCreatingVersion ? 'New Version' : 'New Endpoint';
    }

    get endpointModalSubtitle() {
        if (this.isEditingEndpoint) {
            return 'Update the Rest_Config__mdt record through a metadata deployment.';
        }
        return this.isCreatingVersion
            ? 'Create another version for this route through a metadata deployment.'
            : 'Create a Rest_Config__mdt record through a metadata deployment.';
    }

    get endpointSubmitLabel() {
        if (this.isCreatingVersion) return 'Create Version';
        return this.isEditingEndpoint ? 'Save Endpoint' : 'Create Endpoint';
    }

    get endpointSubmitIconName() {
        return this.isEditingEndpoint ? 'utility:save' : 'utility:add';
    }

    handleRefresh() {
        this.isEditingSettings = false;
        this.loadState();
    }

    startRefresh() {
        this.stopRefresh();
        this.refreshTimer = setInterval(() => {
            if (!this.isLoading && !this.isSavingSettings && !this.isCreatingEndpoint) {
                this.loadState();
            }
        }, REFRESH_INTERVAL_MS);
    }

    stopRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = undefined;
        }
    }

    async loadState() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const state = await getState();
            this.state = state;
            this.routes = this.buildRoutes(state?.routes || []);
            this.restClassOptions = state?.restClasses || [];
            this.settings = state?.settings || {};
            this.settingsDraft = this.toSettingsDraft(this.settings);
            this.metrics = this.buildMetrics(state);
            this.isEditingSettings = false;
        } catch (error) {
            this.state = undefined;
            this.routes = [];
            this.restClassOptions = [];
            this.settings = {};
            this.metrics = this.emptyMetrics();
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isLoading = false;
        }
    }

    handleEditEndpoint(event) {
        const endpointKey = event.currentTarget.dataset.endpointKey;
        const endpoint = this.findEndpoint(endpointKey);
        if (!endpoint) return;

        this.editingEndpointKey = endpoint.key;
        this.versionRouteKey = undefined;
        this.endpointDraft = {
            developerName: endpoint.developerName || '',
            label: endpoint.label || '',
            route: endpoint.route || '',
            version: endpoint.version,
            apexClass: endpoint.apexClass || '',
            active: Boolean(endpoint.isActive),
            defaultVersion: Boolean(endpoint.isDefaultVersion)
        };
        this.isEndpointModalOpen = true;
    }

    handleNewVersion(event) {
        const routeKey = event.currentTarget.dataset.routeKey;
        const route = this.routes.find((candidate) => candidate.key === routeKey);
        if (!route) return;

        const nextVersion = this.nextVersion(route);
        this.editingEndpointKey = undefined;
        this.versionRouteKey = route.key;
        this.endpointDraft = {
            developerName: '',
            label: `${route.route} v${nextVersion}`,
            route: route.route,
            version: nextVersion,
            apexClass: route.mainVersion.apexClass || '',
            active: true,
            defaultVersion: false
        };
        this.isEndpointModalOpen = true;
    }

    handleToggleEndpoint(event) {
        const routeKey = event.currentTarget.dataset.routeKey;
        if (!routeKey) return;

        const expandedEndpointKeys = new Set(this.expandedEndpointKeys);
        if (expandedEndpointKeys.has(routeKey)) {
            expandedEndpointKeys.delete(routeKey);
        } else {
            expandedEndpointKeys.add(routeKey);
        }
        this.expandedEndpointKeys = expandedEndpointKeys;
        this.routes = this.buildRoutes(this.state?.routes || []);
    }

    handleToggleVersions(event) {
        const routeKey = event.currentTarget.dataset.routeKey;
        if (!routeKey) return;

        const expandedRouteKeys = new Set(this.expandedRouteKeys);
        if (expandedRouteKeys.has(routeKey)) {
            expandedRouteKeys.delete(routeKey);
        } else {
            expandedRouteKeys.add(routeKey);
        }
        this.expandedRouteKeys = expandedRouteKeys;
        this.routes = this.buildRoutes(this.state?.routes || []);
    }

    handleSettingChange(event) {
        const field = event.target.dataset.field;
        this.settingsDraft = {
            ...this.settingsDraft,
            [field]: event.target.type === 'checkbox' || event.target.type === 'toggle' ? event.target.checked : event.target.value
        };
    }

    handleEditSettings() {
        this.isEditingSettings = true;
    }

    handleCancelSettingsEdit() {
        this.settingsDraft = this.toSettingsDraft(this.settings);
        this.isEditingSettings = false;
    }

    async handleSaveSettings() {
        this.isSavingSettings = true;
        this.errorMessage = undefined;

        try {
            const state = await saveSettings({
                unknownRouteStatusCode: this.numberOrNull(this.settingsDraft.unknownRouteStatusCode),
                inactiveRouteStatusCode: this.numberOrNull(this.settingsDraft.inactiveRouteStatusCode),
                unsupportedMethodStatusCode: this.numberOrNull(this.settingsDraft.unsupportedMethodStatusCode),
                accessDeniedStatusCode: this.numberOrNull(this.settingsDraft.accessDeniedStatusCode),
                exposeErrorDetails: Boolean(this.settingsDraft.exposeErrorDetails)
            });
            this.state = state;
            this.routes = this.buildRoutes(state?.routes || []);
            this.restClassOptions = state?.restClasses || [];
            this.settings = state?.settings || {};
            this.settingsDraft = this.toSettingsDraft(this.settings);
            this.metrics = this.buildMetrics(state);
            this.isEditingSettings = false;
            this.showToast('REST settings saved', 'Organization REST settings were updated.', 'success');
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
            this.showToast('Settings not saved', this.errorMessage, 'error');
        } finally {
            this.lastRefreshedAt = new Date();
            this.isSavingSettings = false;
        }
    }

    handleOpenEndpointModal() {
        this.editingEndpointKey = undefined;
        this.versionRouteKey = undefined;
        this.endpointDraft = this.newEndpointDraft();
        this.isEndpointModalOpen = true;
    }

    handleCloseEndpointModal() {
        if (!this.isCreatingEndpoint) {
            this.isEndpointModalOpen = false;
            this.editingEndpointKey = undefined;
            this.versionRouteKey = undefined;
        }
    }

    handleEndpointChange(event) {
        const field = event.target.dataset.field;
        this.endpointDraft = {
            ...this.endpointDraft,
            [field]: event.target.type === 'checkbox' || event.target.type === 'toggle' ? event.target.checked : event.target.value
        };
    }

    async handleCreateEndpoint() {
        this.isCreatingEndpoint = true;
        this.errorMessage = undefined;

        try {
            const result = await createEndpoint({
                developerName: this.endpointDraft.developerName,
                label: this.endpointDraft.label,
                route: this.endpointDraft.route,
                version: this.numberOrNull(this.endpointDraft.version),
                apexClass: this.endpointDraft.apexClass,
                active: Boolean(this.endpointDraft.active),
                defaultVersion: Boolean(this.endpointDraft.defaultVersion)
            });
            const wasEditing = this.isEditingEndpoint;
            const wasCreatingVersion = this.isCreatingVersion;
            this.endpointDraft = this.newEndpointDraft();
            this.showToast(
                wasEditing ? 'Endpoint update queued' : 'Endpoint deployment queued',
                `${wasEditing ? 'Updated' : wasCreatingVersion ? 'Created version' : 'Created'} ${result.fullName}. Job ${result.deploymentJobId}.`,
                'success'
            );
            this.isEndpointModalOpen = false;
            this.editingEndpointKey = undefined;
            this.versionRouteKey = undefined;
            await this.loadState();
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
            this.showToast('Endpoint not created', this.errorMessage, 'error');
        } finally {
            this.isCreatingEndpoint = false;
        }
    }

    toSettingsDraft(settings = {}) {
        return {
            unknownRouteStatusCode: settings.unknownRouteStatusCode,
            inactiveRouteStatusCode: settings.inactiveRouteStatusCode,
            unsupportedMethodStatusCode: settings.unsupportedMethodStatusCode,
            accessDeniedStatusCode: settings.accessDeniedStatusCode,
            exposeErrorDetails: Boolean(settings.exposeErrorDetails)
        };
    }

    toDisplayValue(value, effectiveValue) {
        if (value === undefined || value === null || value === '') {
            return effectiveValue === undefined || effectiveValue === null ? 'Default' : `Default (${effectiveValue})`;
        }
        return value;
    }

    newEndpointDraft() {
        return {
            developerName: '',
            label: '',
            route: '',
            version: 1,
            apexClass: '',
            active: true,
            defaultVersion: false
        };
    }

    buildRoutes(rows) {
        const groupsByRoute = new Map();
        rows.forEach((row) => {
            const routeKey = row.route || '';
            const versions = groupsByRoute.get(routeKey) || [];
            versions.push(this.buildRouteVersion(row));
            groupsByRoute.set(routeKey, versions);
        });

        return Array.from(groupsByRoute.keys())
            .sort()
            .map((routeKey) => this.buildRouteGroup(routeKey, groupsByRoute.get(routeKey)));
    }

    buildRouteVersion(row) {
        return {
            ...row,
            key: row.id || row.developerName,
            activeLabel: row.isActive ? 'Active' : 'Inactive',
            statusClass: row.isActive ? 'status-pill status-active' : 'status-pill status-inactive',
            cardClass: this.routeCardClass(row),
            numericVersion: row.version || 0
        };
    }

    buildRouteGroup(routeKey, versions) {
        const sortedVersions = [...versions].sort((left, right) => right.numericVersion - left.numericVersion);
        const mainVersion =
            sortedVersions.find((version) => version.isDefaultVersion && version.isActive) ||
            sortedVersions.find((version) => version.isDefaultVersion) ||
            sortedVersions.find((version) => version.isActive) ||
            sortedVersions[0];
        const otherVersions = sortedVersions.filter((version) => version.key !== mainVersion.key);
        const endpointExpanded = this.expandedEndpointKeys.has(routeKey);
        const versionsExpanded = this.expandedRouteKeys.has(routeKey);

        return {
            key: routeKey,
            route: routeKey,
            label: mainVersion.label,
            mainVersion,
            otherVersions,
            hasOtherVersions: otherVersions.length > 0,
            allVersions: sortedVersions,
            endpointExpanded,
            versionsExpanded,
            showRouteDetails: endpointExpanded,
            showOtherVersions: endpointExpanded && versionsExpanded && otherVersions.length > 0,
            otherVersionCountLabel: `${otherVersions.length} ${otherVersions.length === 1 ? 'other version' : 'other versions'}`,
            endpointToggleIconName: endpointExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            endpointToggleAlternativeText: endpointExpanded ? 'Collapse endpoint' : 'Expand endpoint',
            endpointToggleTitle: endpointExpanded ? 'Collapse endpoint' : 'Expand endpoint',
            versionToggleIconName: versionsExpanded ? 'utility:chevrondown' : 'utility:chevronright',
            versionToggleAlternativeText: versionsExpanded ? 'Collapse route versions' : 'Expand route versions',
            versionToggleTitle: versionsExpanded ? 'Collapse route versions' : 'Expand route versions',
            cardClass: mainVersion.cardClass
        };
    }

    nextVersion(route) {
        const highestVersion = route.allVersions.reduce((highest, version) => {
            return version.numericVersion > highest ? version.numericVersion : highest;
        }, 0);
        return highestVersion + 1;
    }

    findEndpoint(endpointKey) {
        for (const route of this.routes) {
            if (route.mainVersion.key === endpointKey) {
                return route.mainVersion;
            }
            const match = route.otherVersions.find((version) => version.key === endpointKey);
            if (match) {
                return match;
            }
        }
        return undefined;
    }

    routeCardClass(row) {
        const classes = ['route-card'];
        if (!row.isActive) {
            classes.push('route-card-inactive');
        }
        if (row.isDefaultVersion) {
            classes.push('route-card-default');
        }
        return classes.join(' ');
    }

    buildMetrics(state = {}) {
        return METRIC_DEFINITIONS.map((metric) => ({
            ...metric,
            value: new Intl.NumberFormat().format(state?.[metric.id] || 0)
        }));
    }

    emptyMetrics() {
        return METRIC_DEFINITIONS.map((metric) => ({
            ...metric,
            value: '0'
        }));
    }

    numberOrNull(value) {
        if (value === undefined || value === null || value === '') {
            return null;
        }

        return Number(value);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load REST console state.';
    }
}
