import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCompleted from '@salesforce/apex/ThreadMonitorController.getCompleted';

const COLUMNS = [
    {
        label: 'Open',
        type: 'button',
        initialWidth: 90,
        typeAttributes: {
            label: 'Open',
            name: 'open',
            title: 'Open thread record',
            variant: 'base'
        }
    },
    { label: 'Thread', fieldName: 'threadNumber', sortable: true, initialWidth: 120 },
    { label: 'Pool', fieldName: 'pool', sortable: true, initialWidth: 140 },
    { label: 'Thread Key', fieldName: 'threadKey', sortable: true },
    { label: 'Completed', fieldName: 'completedAt', type: 'date', sortable: true, initialWidth: 180 },
    { label: 'Started', fieldName: 'startedAt', type: 'date', sortable: true, initialWidth: 180 },
    { label: 'Last Heartbeat', fieldName: 'heartbeatAt', type: 'date', sortable: true, initialWidth: 180 },
    { label: 'Run Key', fieldName: 'runKey', initialWidth: 150 },
    { label: 'Created By', fieldName: 'createdBy', initialWidth: 160 },
    { label: 'Created Date', fieldName: 'createdDate', type: 'date', sortable: true, initialWidth: 180 }
];

export default class ThreadCompleted extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    rows = [];
    isLoading = false;
    errorMessage;
    searchTerm = '';
    sortBy = 'completedAt';
    sortDirection = 'desc';
    searchRefreshTimer;

    connectedCallback() {
        this.loadRows();
    }

    disconnectedCallback() {
        this.clearSearchRefreshTimer();
    }

    get recordCountLabel() {
        const count = this.rows.length;
        return `${count} ${count === 1 ? 'record' : 'records'}`;
    }

    get refreshButtonClass() {
        return this.isLoading ? 'refresh-button is-refreshing' : 'refresh-button';
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    handleRefresh() {
        this.loadRows();
    }

    @api
    refresh() {
        this.loadRows();
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.queueSearchRefresh();
    }

    handleTableSearchChange(event) {
        this.searchTerm = event.detail.value;
        this.queueSearchRefresh();
    }

    queueSearchRefresh() {
        this.clearSearchRefreshTimer();
        this.searchRefreshTimer = setTimeout(() => {
            this.loadRows();
        }, 250);
    }

    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
        this.loadRows();
    }

    handleRowAction(event) {
        const { action, row } = event.detail;

        if (action.name === 'open' && row.id) {
            this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.id,
                    objectApiName: 'Thread__c',
                    actionName: 'view'
                }
            }).then((url) => {
                window.open(url, '_blank', 'noopener');
            });
        }
    }

    async loadRows() {
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

    clearSearchRefreshTimer() {
        if (this.searchRefreshTimer) {
            clearTimeout(this.searchRefreshTimer);
            this.searchRefreshTimer = undefined;
        }
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load completed threads.';
    }
}
