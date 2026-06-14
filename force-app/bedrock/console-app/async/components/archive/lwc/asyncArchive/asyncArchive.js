import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getArchives from '@salesforce/apex/AsyncArchiveController.getArchives';
import isArchiveRunning from '@salesforce/apex/AsyncArchiveController.isArchiveRunning';
import runNow from '@salesforce/apex/AsyncArchiveController.runNow';

const COLUMNS = [
    { label: 'Archive', fieldName: 'archiveNumber', sortable: true, initialWidth: 130 },
    { label: 'Apex Class', fieldName: 'apexClass', sortable: true },
    { label: 'Record Id', fieldName: 'recordId', sortable: true },
    { label: 'Thread', fieldName: 'thread', sortable: true },
    { label: 'Archived Date', fieldName: 'createdDate', type: 'date', sortable: true, initialWidth: 180 }
];

export default class AsyncArchive extends LightningElement {
    columns = COLUMNS;
    rows = [];
    isArchiveRunning = false;
    isLoading = false;
    isRunningAction = false;
    errorMessage;
    lastRefreshedAt;
    searchTerm = '';
    sortBy = 'createdDate';
    sortDirection = 'desc';
    searchRefreshTimer;

    connectedCallback() {
        this.loadArchive();
    }

    disconnectedCallback() {
        if (this.searchRefreshTimer) {
            clearTimeout(this.searchRefreshTimer);
            this.searchRefreshTimer = undefined;
        }
    }

    get recordCountLabel() {
        const count = this.rows.length;
        return `${count} ${count === 1 ? 'record' : 'records'}`;
    }

    get lastRefreshedLabel() {
        if (!this.lastRefreshedAt) {
            return 'Last refreshed: Not yet';
        }

        return `Last refreshed: ${this.lastRefreshedAt.toLocaleTimeString()}`;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get isRunDisabled() {
        return this.isLoading || this.isRunningAction || this.isArchiveRunning;
    }

    handleRefresh() {
        this.loadArchive();
    }

    @api
    refreshCount() {
        this.loadArchive();
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;

        if (this.searchRefreshTimer) {
            clearTimeout(this.searchRefreshTimer);
        }

        this.searchRefreshTimer = setTimeout(() => {
            this.loadArchive();
        }, 250);
    }

    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
        this.loadArchive();
    }

    async handleRunNow() {
        this.isRunningAction = true;
        this.errorMessage = undefined;

        try {
            await runNow();
            this.isArchiveRunning = true;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Archive job started',
                    message: 'Async archiving is running.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.isRunningAction = false;
        }
    }

    async loadArchive() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const [rows, running] = await Promise.all([
                getArchives({
                    searchTerm: this.searchTerm,
                    sortBy: this.sortBy,
                    sortDirection: this.sortDirection
                }),
                isArchiveRunning()
            ]);
            this.rows = rows;
            this.isArchiveRunning = running;
        } catch (error) {
            this.rows = [];
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isLoading = false;
            this.dispatchCountChange();
        }
    }

    dispatchCountChange() {
        this.dispatchEvent(
            new CustomEvent('countchange', {
                detail: { count: this.rows.length }
            })
        );
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load archived async jobs.';
    }
}
