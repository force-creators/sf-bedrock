import { LightningElement } from 'lwc';
import getBacklog from '@salesforce/apex/AsyncBacklogController.getBacklog';

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

export default class AsyncBacklog extends LightningElement {
    columns = COLUMNS;
    autoRefreshOptions = AUTO_REFRESH_OPTIONS;
    autoRefreshInterval = 'off';
    treeRows = [];
    expandedRows = [];
    isLoading = false;
    errorMessage;
    lastRefreshedAt;
    autoRefreshTimer;

    connectedCallback() {
        this.loadBacklog();
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

    handleRefresh() {
        this.loadBacklog();
    }

    handleAutoRefreshChange(event) {
        this.autoRefreshInterval = event.detail.value;
        this.stopAutoRefresh();

        if (this.autoRefreshInterval === 'off') {
            return;
        }

        this.autoRefreshTimer = setInterval(() => {
            if (!this.isLoading) {
                this.loadBacklog();
            }
        }, Number(this.autoRefreshInterval) * 1000);
    }

    async loadBacklog() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const groups = await getBacklog();
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
        } catch (error) {
            this.treeRows = [];
            this.expandedRows = [];
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
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

        return error?.body?.message || error?.message || 'Unable to load the async backlog.';
    }
}
