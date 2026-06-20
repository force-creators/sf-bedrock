import { LightningElement } from 'lwc';
import getMetrics from '@salesforce/apex/AsyncDashboardController.getMetrics';

const PAGE_SELECTORS = ['c-async-backlog', 'c-async-errors', 'c-async-completed'];

const METRIC_DEFINITIONS = [
    { id: 'backlogCount', label: 'Backlog', className: 'metric metric-backlog' },
    { id: 'runningThreads', label: 'Running Threads', className: 'metric metric-thread' },
    { id: 'errors', label: 'Errors', className: 'metric metric-error' },
    { id: 'jobsCompletedToday', label: 'Completed Today', className: 'metric metric-success' }
];

export default class AsyncLayout extends LightningElement {
    metrics = {};
    isRefreshing = false;
    metricsErrorMessage;
    lastRefreshedAt;

    connectedCallback() {
        this.refreshAll();
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
            return 'Last refreshed: Not yet';
        }

        return `Last refreshed: ${this.lastRefreshedAt.toLocaleTimeString()}`;
    }

    get refreshButtonLabel() {
        return this.isRefreshing ? 'Refreshing…' : 'Refresh';
    }

    handleRefresh() {
        this.refreshAll();
    }

    handlePageCountChange() {
        // A page's record count changed (e.g. retry/delete) — resync the counts only.
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

    async refreshAll() {
        if (this.isRefreshing) {
            return;
        }

        // Tell every rendered page it's time to refresh alongside the counts.
        this.refreshPages();
        await this.loadMetrics();
    }

    async loadMetrics() {
        this.isRefreshing = true;
        this.metricsErrorMessage = undefined;

        try {
            this.metrics = await getMetrics();
        } catch (error) {
            this.metrics = {};
            this.metricsErrorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isRefreshing = false;
        }
    }

    refreshPages() {
        PAGE_SELECTORS.forEach((selector) => this.refreshPage(selector));
    }

    refreshPage(selector) {
        Promise.resolve().then(() => {
            const page = this.template.querySelector(selector);

            if (page?.refresh) {
                page.refresh();
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
