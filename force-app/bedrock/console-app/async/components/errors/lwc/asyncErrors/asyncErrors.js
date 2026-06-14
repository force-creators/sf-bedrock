import { LightningElement, api } from 'lwc';
import getErrors from '@salesforce/apex/AsyncErrorsController.getErrors';
import retryErrors from '@salesforce/apex/AsyncErrorsController.retryErrors';
import deleteErrors from '@salesforce/apex/AsyncErrorsController.deleteErrors';
import LightningConfirm from 'lightning/confirm';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    { label: 'Thread', fieldName: 'threadLabel', initialWidth: 220 },
    { label: 'Class', fieldName: 'apexClass' },
    { label: 'Record Id', fieldName: 'recordId' },
    { label: 'Error Message', fieldName: 'errorMessage', wrapText: true },
    { label: 'Error Stack Trace', fieldName: 'errorStackTrace', wrapText: true }
];

export default class AsyncErrors extends LightningElement {
    columns = COLUMNS;
    treeRows = [];
    expandedRows = [];
    isLoading = false;
    errorMessage;
    selectedRowIds = [];
    selectedWorkItemIds = [];

    connectedCallback() {
        this.loadErrors();
    }

    get recordCountLabel() {
        const count = this.treeRows.reduce((total, group) => total + group._children.length, 0);
        return `${count} ${count === 1 ? 'record' : 'records'}`;
    }

    get refreshButtonClass() {
        return this.isLoading ? 'refresh-button is-refreshing' : 'refresh-button';
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
    refresh() {
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
                    threadLabel: group.threadLabel
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

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load the async errors.';
    }
}
