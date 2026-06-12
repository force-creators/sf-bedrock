import { LightningElement } from 'lwc';
import getCompleted from '@salesforce/apex/AsyncCompletedController.getCompleted';

const COLUMNS = [
    { label: 'Async Job', fieldName: 'asyncJobNumber', sortable: true, initialWidth: 130 },
    { label: 'Apex Class', fieldName: 'apexClass', sortable: true },
    { label: 'Record Id', fieldName: 'recordId', sortable: true },
    { label: 'Thread', fieldName: 'thread', sortable: true },
    { label: 'Created Date', fieldName: 'createdDate', type: 'date', sortable: true, initialWidth: 180 }
];

export default class AsyncCompleted extends LightningElement {
    columns = COLUMNS;
    rows = [];
    isLoading = false;
    errorMessage;
    lastRefreshedAt;
    searchTerm = '';
    sortBy = 'createdDate';
    sortDirection = 'desc';
    searchRefreshTimer;

    connectedCallback() {
        this.loadCompleted();
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

    handleRefresh() {
        this.loadCompleted();
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;

        if (this.searchRefreshTimer) {
            clearTimeout(this.searchRefreshTimer);
        }

        this.searchRefreshTimer = setTimeout(() => {
            this.loadCompleted();
        }, 250);
    }

    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
        this.loadCompleted();
    }

    async loadCompleted() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            this.rows = await getCompleted({
                searchTerm: this.searchTerm,
                sortBy: this.sortBy,
                sortDirection: this.sortDirection
            });
        } catch (error) {
            this.rows = [];
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isLoading = false;
        }
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load completed async jobs.';
    }
}
