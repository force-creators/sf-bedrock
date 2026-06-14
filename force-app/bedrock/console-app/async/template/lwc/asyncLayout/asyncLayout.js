import { LightningElement } from 'lwc';
import getMetrics from '@salesforce/apex/AsyncDashboardController.getMetrics';

const REFRESH_INTERVAL_MS = 15000;

const METRIC_DEFINITIONS = [
    { id: 'backlogCount', label: 'Backlog', className: 'metric metric-backlog' },
    { id: 'runningThreads', label: 'Running Threads', className: 'metric metric-thread' },
    { id: 'errors', label: 'Errors', className: 'metric metric-error' },
    { id: 'jobsCompletedToday', label: 'Completed Today', className: 'metric metric-success' }
];

export default class AsyncLayout extends LightningElement {
    metrics = {};
    isLoadingMetrics = false;
    metricsErrorMessage;
    lastRefreshedAt;
    refreshTimer;

    connectedCallback() {
        this.loadMetrics();
        this.startMetricsRefresh();
    }

    disconnectedCallback() {
        this.stopMetricsRefresh();
    }

    get metricCards() {
        return METRIC_DEFINITIONS.map((metric) => ({
            ...metric,
            value: this.formatNumber(this.metrics?.[metric.id] || 0)
        }));
    }

    get hasMetricsError() {
        return Boolean(this.metricsErrorMessage);
    }

    get lastRefreshedLabel() {
        if (!this.lastRefreshedAt) {
            return 'Counts last refreshed: Not yet';
        }

        return `Counts last refreshed: ${this.lastRefreshedAt.toLocaleTimeString()}`;
    }

    handleRefreshCounts() {
        this.loadMetrics();
    }

    handlePageCountChange() {
        this.loadMetrics();
    }

    handleTabActive(event) {
        const selectedTab = event.target?.value;

        if (selectedTab === 'backlog') {
            this.refreshPage('c-async-backlog');
        }

        if (selectedTab === 'errors') {
            this.refreshPage('c-async-errors');
        }

        if (selectedTab === 'completed') {
            this.refreshPage('c-async-completed');
        }

        if (selectedTab === 'archive') {
            this.refreshPage('c-async-archive');
        }
    }

    async loadMetrics() {
        this.isLoadingMetrics = true;
        this.metricsErrorMessage = undefined;

        try {
            this.metrics = await getMetrics();
        } catch (error) {
            this.metrics = {};
            this.metricsErrorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isLoadingMetrics = false;
        }
    }

    startMetricsRefresh() {
        this.stopMetricsRefresh();
        this.refreshTimer = setInterval(() => {
            if (!this.isLoadingMetrics) {
                this.loadMetrics();
            }
        }, REFRESH_INTERVAL_MS);
    }

    stopMetricsRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = undefined;
        }
    }

    refreshPage(selector) {
        Promise.resolve().then(() => {
            const page = this.template.querySelector(selector);

            if (page?.refreshCount) {
                page.refreshCount();
            }
        });
    }

    formatNumber(value) {
        return new Intl.NumberFormat().format(value);
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load async counts.';
    }
}
