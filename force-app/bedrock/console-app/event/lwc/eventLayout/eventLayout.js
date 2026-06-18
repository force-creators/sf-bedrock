import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getState from '@salesforce/apex/EventConsoleController.getState';

const AUTO_REFRESH_OPTIONS = [
    { label: 'Auto-Refresh Off', value: 'off' },
    { label: '5 seconds', value: '5' },
    { label: '10 seconds', value: '10' },
    { label: '15 seconds', value: '15' },
    { label: '30 seconds', value: '30' },
    { label: '60 seconds', value: '60' }
];

const METRIC_DEFINITIONS = [
    { id: 'backlog', label: 'Backlog', className: 'metric metric-pending' },
    { id: 'running', label: 'Running', className: 'metric metric-running' },
    { id: 'errors', label: 'Errors', className: 'metric metric-error' },
    { id: 'publishedToday', label: 'Published Today', className: 'metric metric-success' }
];

const OPEN_COLUMN = {
    label: 'Open',
    type: 'button',
    initialWidth: 90,
    typeAttributes: {
        label: 'Open',
        name: 'open',
        title: 'Open event record',
        variant: 'base'
    }
};

const WORK_COLUMNS = [
    OPEN_COLUMN,
    { label: 'Event', fieldName: 'eventNumber', sortable: true, initialWidth: 130 },
    { label: 'Status', fieldName: 'status', sortable: true, initialWidth: 120 },
    { label: 'Route', fieldName: 'route', sortable: true },
    { label: 'Payload Type', fieldName: 'payloadType', sortable: true },
    { label: 'Thread', fieldName: 'threadName', sortable: true, initialWidth: 140 },
    { label: 'Thread Key', fieldName: 'threadKey', sortable: true },
    { label: 'Created By', fieldName: 'createdBy', sortable: true, initialWidth: 160 },
    { label: 'Created Date', fieldName: 'createdDate', type: 'date', sortable: true, initialWidth: 180 },
    { label: 'Updated Date', fieldName: 'lastModifiedDate', type: 'date', sortable: true, initialWidth: 180 }
];

const ERROR_COLUMNS = [
    OPEN_COLUMN,
    { label: 'Event', fieldName: 'eventNumber', sortable: true, initialWidth: 130 },
    { label: 'Status', fieldName: 'status', sortable: true, initialWidth: 120 },
    { label: 'Route', fieldName: 'route', sortable: true, initialWidth: 180 },
    { label: 'Thread', fieldName: 'threadName', sortable: true, initialWidth: 140 },
    { label: 'Retry Count', fieldName: 'retryCount', type: 'number', sortable: true, initialWidth: 130 },
    { label: 'Error Message', fieldName: 'errorMessage', wrapText: true },
    { label: 'Updated Date', fieldName: 'lastModifiedDate', type: 'date', sortable: true, initialWidth: 180 }
];

const CONFIG_COLUMNS = [
    { label: 'Payload Type', fieldName: 'payloadType', sortable: true },
    { label: 'Route', fieldName: 'route', sortable: true },
    { label: 'Work Items', fieldName: 'workItems', type: 'number', sortable: true, initialWidth: 140 }
];

export default class EventLayout extends NavigationMixin(LightningElement) {
    autoRefreshOptions = AUTO_REFRESH_OPTIONS;
    autoRefreshInterval = '15';
    workColumns = WORK_COLUMNS;
    errorColumns = ERROR_COLUMNS;
    configColumns = CONFIG_COLUMNS;
    metrics = {};
    backlogRows = [];
    runningRows = [];
    errorRows = [];
    archiveRows = [];
    configRows = [];
    settings = {};
    isRefreshing = false;
    errorMessage;
    lastRefreshedAt;
    refreshTimer;
    backlogSortBy = 'createdDate';
    backlogSortDirection = 'asc';
    runningSortBy = 'lastModifiedDate';
    runningSortDirection = 'desc';
    errorSortBy = 'lastModifiedDate';
    errorSortDirection = 'desc';
    archiveSortBy = 'lastModifiedDate';
    archiveSortDirection = 'desc';
    configSortBy = 'payloadType';
    configSortDirection = 'asc';

    connectedCallback() {
        this.refreshAll();
        this.startAutoRefresh();
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
    }

    get metricCards() {
        return METRIC_DEFINITIONS.map((metric) => ({
            ...metric,
            value: this.formatNumber(this.metrics?.[metric.id] || 0)
        }));
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get hasBacklogRows() {
        return this.backlogRows.length > 0;
    }

    get hasRunningRows() {
        return this.runningRows.length > 0;
    }

    get hasErrorRows() {
        return this.errorRows.length > 0;
    }

    get hasArchiveRows() {
        return this.archiveRows.length > 0;
    }

    get hasConfigRows() {
        return this.configRows.length > 0;
    }

    get backlogCountLabel() {
        return this.recordCountLabel(this.backlogRows.length);
    }

    get runningCountLabel() {
        return this.recordCountLabel(this.runningRows.length);
    }

    get errorCountLabel() {
        return this.recordCountLabel(this.errorRows.length);
    }

    get archiveCountLabel() {
        return this.recordCountLabel(this.archiveRows.length);
    }

    get configCountLabel() {
        return this.recordCountLabel(this.configRows.length);
    }

    get publishBatchSize() {
        return this.formatNumber(this.settings?.publishBatchSize || 0);
    }

    get limitThresholdPct() {
        return `${this.settings?.limitThresholdPct || 0}%`;
    }

    get publishPool() {
        return this.settings?.publishPool || 'EventRelayPublish';
    }

    get lastRefreshedLabel() {
        if (!this.lastRefreshedAt) {
            return 'Last refreshed: Not yet';
        }

        return `Last refreshed: ${this.lastRefreshedAt.toLocaleTimeString()}`;
    }

    get refreshButtonLabel() {
        return this.isRefreshing ? 'Refreshing...' : 'Refresh';
    }

    handleRefresh() {
        this.refreshAll();
    }

    handleAutoRefreshChange(event) {
        this.autoRefreshInterval = event.detail.value;
        this.startAutoRefresh();
    }

    handleBacklogSort(event) {
        this.backlogSortBy = event.detail.fieldName;
        this.backlogSortDirection = event.detail.sortDirection;
        this.backlogRows = this.sortRows(this.backlogRows, this.backlogSortBy, this.backlogSortDirection);
    }

    handleRunningSort(event) {
        this.runningSortBy = event.detail.fieldName;
        this.runningSortDirection = event.detail.sortDirection;
        this.runningRows = this.sortRows(this.runningRows, this.runningSortBy, this.runningSortDirection);
    }

    handleErrorSort(event) {
        this.errorSortBy = event.detail.fieldName;
        this.errorSortDirection = event.detail.sortDirection;
        this.errorRows = this.sortRows(this.errorRows, this.errorSortBy, this.errorSortDirection);
    }

    handleArchiveSort(event) {
        this.archiveSortBy = event.detail.fieldName;
        this.archiveSortDirection = event.detail.sortDirection;
        this.archiveRows = this.sortRows(this.archiveRows, this.archiveSortBy, this.archiveSortDirection);
    }

    handleConfigSort(event) {
        this.configSortBy = event.detail.fieldName;
        this.configSortDirection = event.detail.sortDirection;
        this.configRows = this.sortRows(this.configRows, this.configSortBy, this.configSortDirection);
    }

    handleRowAction(event) {
        const { action, row } = event.detail;

        if (action.name === 'open' && row.id) {
            this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.id,
                    objectApiName: 'Event__c',
                    actionName: 'view'
                }
            }).then((url) => {
                window.open(url, '_blank', 'noopener');
            });
        }
    }

    async refreshAll() {
        if (this.isRefreshing) {
            return;
        }

        this.isRefreshing = true;
        this.errorMessage = undefined;

        try {
            const state = await getState();
            this.metrics = state.metrics || {};
            this.backlogRows = this.sortRows(state.backlogRows || [], this.backlogSortBy, this.backlogSortDirection);
            this.runningRows = this.sortRows(state.runningRows || [], this.runningSortBy, this.runningSortDirection);
            this.errorRows = this.sortRows(state.errorRows || [], this.errorSortBy, this.errorSortDirection);
            this.archiveRows = this.sortRows(state.archiveRows || [], this.archiveSortBy, this.archiveSortDirection);
            this.configRows = this.sortRows(state.configRows || [], this.configSortBy, this.configSortDirection);
            this.settings = state.settings || {};
        } catch (error) {
            this.metrics = {};
            this.backlogRows = [];
            this.runningRows = [];
            this.errorRows = [];
            this.archiveRows = [];
            this.configRows = [];
            this.settings = {};
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isRefreshing = false;
        }
    }

    startAutoRefresh() {
        this.stopAutoRefresh();

        if (this.autoRefreshInterval === 'off') {
            return;
        }

        this.refreshTimer = setInterval(() => {
            if (!this.isRefreshing) {
                this.refreshAll();
            }
        }, Number(this.autoRefreshInterval) * 1000);
    }

    stopAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = undefined;
        }
    }

    sortRows(rows, fieldName, sortDirection) {
        const multiplier = sortDirection === 'asc' ? 1 : -1;
        return [...rows].sort((left, right) => {
            const leftValue = left[fieldName];
            const rightValue = right[fieldName];

            if (leftValue === rightValue) {
                return 0;
            }

            if (leftValue === null || leftValue === undefined) {
                return -1 * multiplier;
            }

            if (rightValue === null || rightValue === undefined) {
                return 1 * multiplier;
            }

            return leftValue > rightValue ? multiplier : -1 * multiplier;
        });
    }

    recordCountLabel(count) {
        return `${count} ${count === 1 ? 'record' : 'records'}`;
    }

    formatNumber(value) {
        return new Intl.NumberFormat().format(value);
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load EventRelay publish work.';
    }
}
