import { LightningElement, api } from 'lwc';
import getErrors from '@salesforce/apex/AsyncErrorsController.getErrors';
import retryErrors from '@salesforce/apex/AsyncErrorsController.retryErrors';
import deleteErrors from '@salesforce/apex/AsyncErrorsController.deleteErrors';
import LightningConfirm from 'lightning/confirm';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    { label: 'Thread / Job', fieldName: 'threadLabel', initialWidth: 220 },
    { label: 'Running User', fieldName: 'runningUser' },
    { label: 'Apex Class', fieldName: 'apexClass' },
    { label: 'Priority', fieldName: 'priority', type: 'number', initialWidth: 110 },
    { label: 'Record Id', fieldName: 'recordId' },
    { label: 'Status', fieldName: 'status', initialWidth: 130 },
    { label: 'Created Date', fieldName: 'createdDate', type: 'date', initialWidth: 180 }
];

const AUTO_REFRESH_OPTIONS = [
    { label: 'Auto-Refresh Off', value: 'off' },
    { label: '5 seconds', value: '5' },
    { label: '10 seconds', value: '10' },
    { label: '15 seconds', value: '15' },
    { label: '30 seconds', value: '30' },
    { label: '60 seconds', value: '60' }
];

export default class AsyncErrors extends LightningElement {
    columns = COLUMNS;
    autoRefreshOptions = AUTO_REFRESH_OPTIONS;
    autoRefreshInterval = 'off';
    treeRows = [];
    expandedRows = [];
    isLoading = false;
    errorMessage;
    lastRefreshedAt;
    autoRefreshTimer;
    selectedRowIds = [];
    selectedWorkItemIds = [];

    connectedCallback() {
        this.loadErrors();
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
    }

    get recordCountLabel() {
        const count = this.treeRows.reduce((total, group) => total + group._children.length, 0);
        return `${count} ${count === 1 ? 'record' : 'records'}`;
    }

    get lastRefreshedLabel() {
        if (!this.lastRefreshedAt) {
            return 'Last refreshed: Not yet';
        }

        return `Last refreshed: ${this.lastRefreshedAt.toLocaleTimeString()}`;
    }

    get hasRows() {
        return this.treeRows.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get hasSelectedRows() {
        return this.selectedWorkItemIds.length > 0;
    }

    get selectedCountLabel() {
        const count = this.selectedWorkItemIds.length;
        return `${count} selected`;
    }

    handleRefresh() {
        this.loadErrors();
    }

    @api
    refreshCount() {
        this.loadErrors();
    }

    handleRowSelection(event) {
        const selectedRowIds = new Set();
        const selectedWorkItemIds = new Set();
        const groupsById = new Map(this.treeRows.map((group) => [group.id, group]));
        const workItemIds = new Set(
            this.treeRows.flatMap((group) => group._children.map((row) => row.id))
        );

        event.detail.selectedRows.forEach((row) => {
            const group = row._children ? row : groupsById.get(row.id);

            if (group) {
                selectedRowIds.add(group.id);
                group._children.forEach((childRow) => {
                    selectedRowIds.add(childRow.id);
                    selectedWorkItemIds.add(childRow.id);
                });
                return;
            }

            if (workItemIds.has(row.id)) {
                selectedRowIds.add(row.id);
                selectedWorkItemIds.add(row.id);
            }
        });

        this.selectedRowIds = [...selectedRowIds];
        this.selectedWorkItemIds = [...selectedWorkItemIds];
    }

    async handleRetrySelected() {
        const confirmed = await LightningConfirm.open({
            label: 'Retry async errors',
            message: `Retry ${this.selectedWorkItemIds.length} selected async error ${this.selectedWorkItemIds.length === 1 ? 'record' : 'records'}?`,
            theme: 'warning',
            variant: 'header'
        });

        if (!confirmed) {
            return;
        }

        await this.runSelectedAction(
            () => retryErrors({ workItemIds: this.selectedWorkItemIds }),
            'Retry queued',
            'Selected async errors were queued for retry.'
        );
    }

    async handleDeleteSelected() {
        const confirmed = await LightningConfirm.open({
            label: 'Delete async errors',
            message: `Delete ${this.selectedWorkItemIds.length} selected async error ${this.selectedWorkItemIds.length === 1 ? 'record' : 'records'}?`,
            theme: 'error',
            variant: 'header'
        });

        if (!confirmed) {
            return;
        }

        await this.runSelectedAction(
            () => deleteErrors({ workItemIds: this.selectedWorkItemIds }),
            'Errors deleted',
            'Selected async errors were deleted.'
        );
    }

    handleAutoRefreshChange(event) {
        this.autoRefreshInterval = event.detail.value;
        this.stopAutoRefresh();

        if (this.autoRefreshInterval === 'off') {
            return;
        }

        this.autoRefreshTimer = setInterval(() => {
            if (!this.isLoading) {
                this.loadErrors();
            }
        }, Number(this.autoRefreshInterval) * 1000);
    }

    async loadErrors() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const groups = await getErrors();
            this.treeRows = groups.map((group) => ({
                id: group.id,
                threadLabel: group.threadLabel,
                status: group.status,
                _children: group.rows.map((row) => ({
                    ...row,
                    threadLabel: row.asyncJobNumber
                }))
            }));
            this.expandedRows = this.treeRows.map((row) => row.id);
            this.selectedRowIds = [];
            this.selectedWorkItemIds = [];
        } catch (error) {
            this.treeRows = [];
            this.expandedRows = [];
            this.selectedRowIds = [];
            this.selectedWorkItemIds = [];
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isLoading = false;
            this.dispatchCountChange();
        }
    }

    dispatchCountChange() {
        const count = this.treeRows.reduce((total, group) => total + group._children.length, 0);
        this.dispatchEvent(
            new CustomEvent('countchange', {
                detail: { count }
            })
        );
    }

    async runSelectedAction(action, title, message) {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const count = await action();
            this.dispatchEvent(
                new ShowToastEvent({
                    title,
                    message: `${message} ${count} ${count === 1 ? 'record was' : 'records were'} affected.`,
                    variant: 'success'
                })
            );
            await this.loadErrors();
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.isLoading = false;
        }
    }

    stopAutoRefresh() {
        if (this.autoRefreshTimer) {
            clearInterval(this.autoRefreshTimer);
            this.autoRefreshTimer = undefined;
        }
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load the async errors.';
    }
}
