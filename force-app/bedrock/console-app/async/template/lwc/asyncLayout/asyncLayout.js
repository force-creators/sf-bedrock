import { LightningElement } from 'lwc';
import getMetrics from '@salesforce/apex/AsyncDashboardController.getMetrics';

export default class AsyncLayout extends LightningElement {
    selectedId = 'dashboard';
    backlogCount = 0;
    errorCount = 0;
    refreshTimer;

    connectedCallback() {
        this.loadCounts();
        this.startCountRefresh();
    }

    disconnectedCallback() {
        this.stopCountRefresh();
    }

    get backlogTabLabel() {
        return `Backlog (${this.backlogCount})`;
    }

    get errorsTabLabel() {
        return `Errors (${this.errorCount})`;
    }

    handleTabActive(event) {
        this.selectedId = event.target.value;

        if (this.selectedId === 'backlog') {
            this.refreshBacklogCountFromPage();
        }

        if (this.selectedId === 'errors') {
            this.refreshErrorCountFromPage();
        }
    }

    handleBacklogCountChange(event) {
        this.backlogCount = event.detail?.count || 0;
    }

    handleErrorsCountChange(event) {
        this.errorCount = event.detail?.count || 0;
    }

    async loadCounts() {
        try {
            const metrics = await getMetrics();
            this.backlogCount = metrics?.backlogCount || 0;
            this.errorCount = metrics?.errors || 0;
        } catch {
            this.backlogCount = 0;
            this.errorCount = 0;
        }
    }

    startCountRefresh() {
        this.stopCountRefresh();
        this.refreshTimer = setInterval(() => {
            this.loadCounts();
        }, 15000);
    }

    stopCountRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = undefined;
        }
    }

    refreshBacklogCountFromPage() {
        const backlog = this.template.querySelector('c-async-backlog');

        if (backlog?.refreshCount) {
            backlog.refreshCount();
        }
    }

    refreshErrorCountFromPage() {
        const errors = this.template.querySelector('c-async-errors');

        if (errors?.refreshCount) {
            errors.refreshCount();
        }
    }
}
