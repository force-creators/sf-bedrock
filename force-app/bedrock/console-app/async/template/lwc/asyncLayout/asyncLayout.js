import { LightningElement } from 'lwc';
import getMetrics from '@salesforce/apex/AsyncDashboardController.getMetrics';

const NAV_ITEMS = [
    { id: 'dashboard', label: 'Dashboard', iconName: 'utility:home' },
    { id: 'backlog', label: 'Backlog', iconName: 'utility:rows' },
    { id: 'completed', label: 'Completed', iconName: 'utility:success' },
    { id: 'errors', label: 'Errors', iconName: 'utility:error' },
    {
        id: 'job-configurations',
        label: 'Job Configurations',
        iconName: 'utility:settings'
    }
];

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

    get navItems() {
        return NAV_ITEMS.map((item) => {
            const isActive = item.id === this.selectedId;
            const isBacklog = item.id === 'backlog';
            const isErrors = item.id === 'errors';

            return {
                ...item,
                count: isBacklog ? this.backlogCount : this.errorCount,
                showCount: isBacklog || isErrors,
                itemClass: `slds-nav-vertical__item${isActive ? ' slds-is-active' : ''}`
            };
        });
    }

    get isDashboard() {
        return this.selectedId === 'dashboard';
    }

    get isBacklog() {
        return this.selectedId === 'backlog';
    }

    get isErrors() {
        return this.selectedId === 'errors';
    }

    get isCompleted() {
        return this.selectedId === 'completed';
    }

    get isJobConfigurations() {
        return this.selectedId === 'job-configurations';
    }

    get isPerformance() {
        return this.selectedId === 'performance';
    }

    get isSettings() {
        return this.selectedId === 'settings';
    }

    handleNavSelect(event) {
        this.selectedId = event.currentTarget.dataset.id;

        if (this.selectedId === 'backlog') {
            Promise.resolve().then(() => {
                this.refreshBacklogCountFromPage();
            });
        }

        if (this.selectedId === 'errors') {
            Promise.resolve().then(() => {
                this.refreshErrorCountFromPage();
            });
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
