import { LightningElement } from "lwc";
import getMetrics from "@salesforce/apex/AsyncDashboardController.getMetrics";

const METRICS = [
    { id: "jobsCompletedToday", label: "Jobs Completed Today", value: "0" },
    { id: "backlogCount", label: "Backlog Count", value: "0" },
    { id: "errors", label: "Errors", value: "0" }
];

export default class AsyncDashboard extends LightningElement {
    metrics = METRICS;
    isLoading = false;
    errorMessage;

    connectedCallback() {
        this.loadMetrics();
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    async loadMetrics() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const values = await getMetrics();
            this.metrics = METRICS.map((metric) => ({
                ...metric,
                value: this.formatCount(values?.[metric.id])
            }));
        } catch (error) {
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.isLoading = false;
        }
    }

    formatCount(value) {
        return new Intl.NumberFormat().format(value || 0);
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(", ");
        }

        return (
            error?.body?.message ||
            error?.message ||
            "Unable to load dashboard metrics."
        );
    }
}
