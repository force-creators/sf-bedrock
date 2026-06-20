import { LightningElement } from 'lwc';
import getState from '@salesforce/apex/EventConsoleController.getState';
import retryWorkItems from '@salesforce/apex/EventConsoleController.retryWorkItems';
import deleteWorkItems from '@salesforce/apex/EventConsoleController.deleteWorkItems';
import LightningConfirm from 'lightning/confirm';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const METRIC_DEFINITIONS = [
    { id: 'backlog', label: 'Backlog', className: 'metric metric-pending' },
    { id: 'errors', label: 'Errors', className: 'metric metric-error' },
    { id: 'running', label: 'Publisher Lanes', className: 'metric metric-running' },
    { id: 'publishedToday', label: 'Published Today', className: 'metric metric-success' }
];

const WORK_COLUMNS = [
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
    { label: 'Event', fieldName: 'eventNumber', sortable: true, initialWidth: 130 },
    { label: 'Status', fieldName: 'status', sortable: true, initialWidth: 120 },
    { label: 'Route', fieldName: 'route', sortable: true, initialWidth: 180 },
    { label: 'Thread', fieldName: 'threadName', sortable: true, initialWidth: 140 },
    { label: 'Retry Count', fieldName: 'retryCount', type: 'number', sortable: true, initialWidth: 130 },
    { label: 'Error Message', fieldName: 'errorMessage', wrapText: true },
    { label: 'Updated Date', fieldName: 'lastModifiedDate', type: 'date', sortable: true, initialWidth: 180 }
];

export default class EventLayout extends LightningElement {
    workColumns = WORK_COLUMNS;
    errorColumns = ERROR_COLUMNS;
    metrics = {};
    backlogRows = [];
    errorRows = [];
    archiveRows = [];
    configRows = [];
    settings = {};
    isRefreshing = false;
    isApplyingErrorAction = false;
    errorMessage;
    lastRefreshedAt;
    selectedErrorRowIds = [];
    backlogSortBy = 'createdDate';
    backlogSortDirection = 'asc';
    errorSortBy = 'lastModifiedDate';
    errorSortDirection = 'desc';
    archiveSortBy = 'lastModifiedDate';
    archiveSortDirection = 'desc';
    configSortBy = 'payloadType';
    configSortDirection = 'asc';

    connectedCallback() {
        this.refreshAll();
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

    get hasErrorRows() {
        return this.errorRows.length > 0;
    }

    get hasArchiveRows() {
        return this.archiveRows.length > 0;
    }

    get hasConfigRows() {
        return this.configRows.length > 0;
    }

    get routeCards() {
        return this.configRows.map((row) => {
            const payloadType = row.payloadType || 'Unspecified Payload';
            const route = row.route || 'Default Route';
            const workItems = row.workItems || 0;
            return {
                id: row.id,
                payloadType,
                route,
                workItems: this.formatNumber(workItems),
                workItemsLabel: `${this.formatNumber(workItems)} ${workItems === 1 ? 'work item' : 'work items'}`,
                badges: [
                    {
                        label: `${this.formatNumber(workItems)} ${workItems === 1 ? 'work item' : 'work items'}`,
                        className: 'work-badge'
                    }
                ]
            };
        });
    }

    get backlogCountLabel() {
        return this.recordCountLabel(this.backlogRows.length);
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

    get eventRouteCountLabel() {
        const count = this.configRows.length;
        return `${count} ${count === 1 ? 'event route' : 'event routes'}`;
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

    get hasSelectedErrorRows() {
        return this.selectedErrorRowIds.length > 0;
    }

    get selectedErrorCountLabel() {
        return this.recordCountLabel(this.selectedErrorRowIds.length);
    }

    get isSelectedErrorActionDisabled() {
        return this.isRefreshing || this.isApplyingErrorAction || !this.hasSelectedErrorRows;
    }

    handleRefresh() {
        this.refreshAll();
    }

    handleBacklogSort(event) {
        this.backlogSortBy = event.detail.fieldName;
        this.backlogSortDirection = event.detail.sortDirection;
        this.backlogRows = this.sortRows(this.backlogRows, this.backlogSortBy, this.backlogSortDirection);
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

    handleErrorSelection(event) {
        this.selectedErrorRowIds = (event.detail.selectedRows || [])
            .map((row) => row.id)
            .filter(Boolean);
    }

    async handleRetrySelected() {
        const confirmed = await LightningConfirm.open({
            label: 'Retry selected events',
            message: `Retry ${this.selectedErrorCountLabel}?`,
            variant: 'header'
        });

        if (!confirmed) {
            return;
        }

        await this.runSelectedErrorAction(
            (workItemIds) => retryWorkItems({ workItemIds }),
            'Retry queued',
            'moved back to pending',
            'Retry failed'
        );
    }

    async handleDeleteSelected() {
        const confirmed = await LightningConfirm.open({
            label: 'Delete selected events',
            message: `Delete ${this.selectedErrorCountLabel}? This removes the selected failed EventRelay work items.`,
            variant: 'header'
        });

        if (!confirmed) {
            return;
        }

        await this.runSelectedErrorAction(
            (workItemIds) => deleteWorkItems({ workItemIds }),
            'Events deleted',
            'deleted',
            'Delete failed'
        );
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
            this.errorRows = this.sortRows(state.errorRows || [], this.errorSortBy, this.errorSortDirection);
            this.archiveRows = this.sortRows(state.archiveRows || [], this.archiveSortBy, this.archiveSortDirection);
            this.configRows = this.sortRows(state.configRows || [], this.configSortBy, this.configSortDirection);
            this.settings = state.settings || {};
            this.selectedErrorRowIds = [];
        } catch (error) {
            this.metrics = {};
            this.backlogRows = [];
            this.errorRows = [];
            this.archiveRows = [];
            this.configRows = [];
            this.settings = {};
            this.selectedErrorRowIds = [];
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isRefreshing = false;
        }
    }

    async runSelectedErrorAction(action, successTitle, successVerb, errorTitle) {
        const workItemIds = [...this.selectedErrorRowIds];
        if (workItemIds.length === 0 || this.isApplyingErrorAction) {
            return;
        }

        this.isApplyingErrorAction = true;
        this.errorMessage = undefined;

        try {
            const actionCount = await action(workItemIds);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: successTitle,
                    message: `${this.formatNumber(actionCount || 0)} ${actionCount === 1 ? 'event' : 'events'} ${successVerb}.`,
                    variant: 'success'
                })
            );
            await this.refreshAll();
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: errorTitle,
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isApplyingErrorAction = false;
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
