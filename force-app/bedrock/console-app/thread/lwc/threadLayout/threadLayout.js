import { LightningElement } from "lwc";
import getMetrics from "@salesforce/apex/ThreadDashboardController.getMetrics";

const PAGE_SELECTORS = ["c-thread-running", "c-thread-completed"];

const METRIC_DEFINITIONS = [
    {
        id: "runningThreads",
        label: "Running",
        className: "metric metric-running"
    },
    {
        id: "pendingThreads",
        label: "Pending",
        className: "metric metric-pending"
    },
    { id: "staleThreads", label: "Stale", className: "metric metric-stale" },
    {
        id: "completedToday",
        label: "Completed Today",
        className: "metric metric-success"
    }
];

export default class ThreadLayout extends LightningElement {
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
            return "Last refreshed: Not yet";
        }

        return `Last refreshed: ${this.lastRefreshedAt.toLocaleTimeString()}`;
    }

    get refreshButtonLabel() {
        return this.isRefreshing ? "Refreshing..." : "Refresh";
    }

    handleRefresh() {
        this.refreshAll();
    }

    handlePageCountChange() {
        this.loadMetrics();
    }

    handleTabActive(event) {
        const selectedTab = event.target?.value;

        if (selectedTab === "running") {
            this.refreshPage("c-thread-running");
        }

        if (selectedTab === "completed") {
            this.refreshPage("c-thread-completed");
        }
    }

    async refreshAll() {
        if (this.isRefreshing) {
            return;
        }

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
            return error.body.map((entry) => entry.message).join(", ");
        }

        return (
            error?.body?.message ||
            error?.message ||
            "Unable to load thread counts."
        );
    }
}
