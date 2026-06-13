import { LightningElement } from 'lwc';
import getSchedule from '@salesforce/apex/SchedulerConsoleController.getSchedule';

const REFRESH_INTERVAL_MS = 15000;
const EMPTY_LABEL = 'Never';

const METRIC_DEFINITIONS = [
    { id: 'enabledJobCount', label: 'Enabled', className: 'metric metric-enabled' },
    { id: 'dueJobCount', label: 'Due Now', className: 'metric metric-due' },
    { id: 'errorJobCount', label: 'With Errors', className: 'metric metric-error' },
    { id: 'disabledJobCount', label: 'Disabled', className: 'metric metric-muted' }
];

export default class SchedulerLayout extends LightningElement {
    jobs = [];
    metrics = this.emptyMetrics();
    isLoading = false;
    errorMessage;
    lastRefreshedAt;
    hasMetadataChanges = false;
    metadataRecalculationAt;
    refreshTimer;

    connectedCallback() {
        this.loadSchedule();
        this.startRefresh();
    }

    disconnectedCallback() {
        this.stopRefresh();
    }

    get hasJobs() {
        return this.jobs.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get metadataRecalculationLabel() {
        return this.formatDateTime(this.metadataRecalculationAt, 'the next Scheduler heartbeat');
    }

    get lastRefreshedLabel() {
        if (!this.lastRefreshedAt) {
            return 'Last refreshed: Not yet';
        }

        return `Last refreshed: ${this.lastRefreshedAt.toLocaleTimeString()}`;
    }

    handleRefresh() {
        this.loadSchedule();
    }

    startRefresh() {
        this.stopRefresh();
        this.refreshTimer = setInterval(() => {
            if (!this.isLoading) {
                this.loadSchedule();
            }
        }, REFRESH_INTERVAL_MS);
    }

    stopRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = undefined;
        }
    }

    async loadSchedule() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const state = await getSchedule();
            this.hasMetadataChanges = Boolean(state?.hasMetadataChanges);
            this.metadataRecalculationAt = state?.metadataRecalculationAt;
            this.metrics = this.buildMetrics(state);
            this.jobs = this.buildJobs(state?.jobs || []);
        } catch (error) {
            this.jobs = [];
            this.metrics = this.emptyMetrics();
            this.hasMetadataChanges = false;
            this.metadataRecalculationAt = undefined;
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isLoading = false;
        }
    }

    buildMetrics(state = {}) {
        return METRIC_DEFINITIONS.map((metric) => ({
            ...metric,
            value: new Intl.NumberFormat().format(state?.[metric.id] || 0)
        }));
    }

    emptyMetrics() {
        return METRIC_DEFINITIONS.map((metric) => ({
            ...metric,
            value: '0'
        }));
    }

    buildJobs(rows) {
        return rows
            .map((row) => {
                const key = row.id || row.configKey;
                const status = row.status || 'Scheduled';

                return {
                    ...row,
                    key,
                    statusClass: this.statusClass(status),
                    timelineClass: `timeline-item ${status === 'Disabled' ? 'timeline-disabled' : ''}`,
                    lastExecutedLabel: this.formatDateTime(row.lastExecutedAt, EMPTY_LABEL),
                    nextScheduledLabel: this.formatDateTime(row.nextScheduledAt, status === 'Disabled' ? 'Paused' : 'Due now')
                };
            })
            .sort((first, second) => this.compareJobs(first, second));
    }

    compareJobs(first, second) {
        const firstTime = first.nextScheduledAt ? new Date(first.nextScheduledAt).getTime() : Number.MAX_SAFE_INTEGER;
        const secondTime = second.nextScheduledAt ? new Date(second.nextScheduledAt).getTime() : Number.MAX_SAFE_INTEGER;

        if (firstTime !== secondTime) {
            return firstTime - secondTime;
        }

        return (first.configKey || '').localeCompare(second.configKey || '');
    }

    statusClass(status) {
        const variant = {
            'Due Now': 'due',
            Disabled: 'disabled',
            Scheduled: 'scheduled'
        }[status] || 'scheduled';

        return `status-pill status-${variant}`;
    }

    formatDateTime(value, fallback) {
        if (!value) {
            return fallback;
        }

        return new Intl.DateTimeFormat(undefined, {
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }).format(new Date(value));
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(', ');
        }

        return error?.body?.message || error?.message || 'Unable to load the Scheduler console.';
    }
}
