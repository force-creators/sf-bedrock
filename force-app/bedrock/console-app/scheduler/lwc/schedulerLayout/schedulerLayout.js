import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSchedule from '@salesforce/apex/SchedulerConsoleController.getSchedule';

const EMPTY_LABEL = 'Never';

const METRIC_DEFINITIONS = [
    { id: 'enabledJobCount', label: 'Enabled', className: 'metric metric-enabled' },
    { id: 'dueJobCount', label: 'Due Now', className: 'metric metric-due' },
    { id: 'errorJobCount', label: 'With Errors', className: 'metric metric-error' },
    { id: 'disabledJobCount', label: 'Disabled', className: 'metric metric-muted' }
];

const JOB_CONFIGURATION_COLUMNS = [
    {
        label: 'Open',
        type: 'button',
        initialWidth: 90,
        typeAttributes: {
            label: 'Open',
            name: 'open',
            title: 'Open scheduler job configuration',
            variant: 'base'
        }
    },
    { label: 'Developer Name', fieldName: 'developerName' },
    { label: 'Label', fieldName: 'label' },
    { label: 'Apex Class', fieldName: 'apexClass' },
    { label: 'Enabled', fieldName: 'isEnabled', type: 'boolean', initialWidth: 110 },
    { label: 'Frequency', fieldName: 'frequency', initialWidth: 130 },
    { label: 'Interval', fieldName: 'frequencyValue', initialWidth: 100 },
    { label: 'Cadence', fieldName: 'cadence', initialWidth: 150 }
];

export default class SchedulerLayout extends NavigationMixin(LightningElement) {
    jobs = [];
    scheduleSections = [];
    jobConfigurationColumns = JOB_CONFIGURATION_COLUMNS;
    jobConfigurations = [];
    metrics = this.emptyMetrics();
    isLoading = false;
    errorMessage;
    lastRefreshedAt;
    hasMetadataChanges = false;
    metadataRecalculationAt;
    errorJobCount = 0;

    connectedCallback() {
        this.loadSchedule();
    }

    get hasJobs() {
        return this.scheduleSections.length > 0;
    }

    get hasJobConfigurations() {
        return this.jobConfigurations.length > 0;
    }

    get jobConfigurationCountLabel() {
        const count = this.jobConfigurations.length;
        return `${count} ${count === 1 ? 'configuration' : 'configurations'}`;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get hasJobErrors() {
        return this.errorJobCount > 0;
    }

    get errorSummaryLabel() {
        return `${this.errorJobCount} scheduler ${this.errorJobCount === 1 ? 'job has' : 'jobs have'} a stored error`;
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

    async loadSchedule() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            const state = await getSchedule();
            this.hasMetadataChanges = Boolean(state?.hasMetadataChanges);
            this.metadataRecalculationAt = state?.metadataRecalculationAt;
            this.errorJobCount = state?.errorJobCount || 0;
            this.metrics = this.buildMetrics(state);
            this.jobs = this.buildJobs(state?.jobs || []);
            this.scheduleSections = this.groupJobs(this.jobs);
            this.jobConfigurations = state?.jobConfigurations || [];
        } catch (error) {
            this.jobs = [];
            this.scheduleSections = [];
            this.jobConfigurations = [];
            this.metrics = this.emptyMetrics();
            this.hasMetadataChanges = false;
            this.metadataRecalculationAt = undefined;
            this.errorJobCount = 0;
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.lastRefreshedAt = new Date();
            this.isLoading = false;
        }
    }

    handleJobConfigurationAction(event) {
        const { action, row } = event.detail;

        if (action.name === 'open' && row.id) {
            this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.id,
                    objectApiName: 'Scheduler_Job__mdt',
                    actionName: 'view'
                }
            }).then((url) => {
                window.open(url, '_blank', 'noopener');
            });
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
        const now = Date.now();

        return rows
            .map((row) => {
                const key = row.id || row.apexClass;
                const status = row.status || 'Scheduled';

                return {
                    ...row,
                    key,
                    statusLabel: this.statusLabel(row, now),
                    statusClass: this.statusClass(status),
                    timelineClass: this.timelineClass(row),
                    lastExecutedLabel: this.formatDateTime(row.lastExecutedAt, EMPTY_LABEL),
                    nextScheduledLabel: this.formatDateTime(row.nextScheduledAt, status === 'Disabled' ? 'Paused' : 'Due now')
                };
            })
            .sort((first, second) => this.compareJobs(first, second));
    }

    groupJobs(jobs) {
        const sections = [];
        const sectionsByKey = new Map();

        jobs.forEach((job) => {
            const section = this.sectionForJob(job);

            if (!sectionsByKey.has(section.key)) {
                sectionsByKey.set(section.key, {
                    ...section,
                    jobs: []
                });
                sections.push(sectionsByKey.get(section.key));
            }

            sectionsByKey.get(section.key).jobs.push(job);
        });

        return sections.map((section) => ({
            ...section,
            countLabel: `${section.jobs.length} ${section.jobs.length === 1 ? 'job' : 'jobs'}`
        }));
    }

    sectionForJob(job) {
        if (job.status === 'Disabled') {
            return {
                key: 'paused',
                label: 'Paused',
                description: 'Disabled scheduler jobs'
            };
        }

        if (job.status === 'Due Now' || !job.nextScheduledAt || new Date(job.nextScheduledAt).getTime() <= Date.now()) {
            return {
                key: 'due-now',
                label: 'Due Now',
                description: 'Ready for the next Scheduler heartbeat'
            };
        }

        const nextRun = new Date(job.nextScheduledAt);
        const today = this.startOfToday();
        const tomorrow = this.addDays(today, 1);
        const dayAfterTomorrow = this.addDays(today, 2);
        const nextWeek = this.addDays(today, 7);
        const followingWeek = this.addDays(today, 14);

        if (nextRun < tomorrow) {
            return {
                key: 'today',
                label: 'Today',
                description: this.formatSectionDate(today)
            };
        }

        if (nextRun < dayAfterTomorrow) {
            return {
                key: 'tomorrow',
                label: 'Tomorrow',
                description: this.formatSectionDate(tomorrow)
            };
        }

        if (nextRun < nextWeek) {
            return {
                key: 'this-week',
                label: 'This Week',
                description: 'Later this week'
            };
        }

        if (nextRun < followingWeek) {
            return {
                key: 'next-week',
                label: 'Next Week',
                description: '7 to 14 days out'
            };
        }

        return {
            key: `date-${nextRun.getFullYear()}-${nextRun.getMonth()}-${nextRun.getDate()}`,
            label: this.formatSectionDate(nextRun),
            description: 'Further out'
        };
    }

    compareJobs(first, second) {
        const firstTime = first.nextScheduledAt ? new Date(first.nextScheduledAt).getTime() : Number.MAX_SAFE_INTEGER;
        const secondTime = second.nextScheduledAt ? new Date(second.nextScheduledAt).getTime() : Number.MAX_SAFE_INTEGER;

        if (firstTime !== secondTime) {
            return firstTime - secondTime;
        }

        return (first.apexClass || '').localeCompare(second.apexClass || '');
    }

    statusLabel(row, now) {
        if (row.status === 'Disabled') {
            return 'Disabled';
        }

        if (row.status === 'Due Now' || !row.nextScheduledAt) {
            return 'Due now';
        }

        const millisecondsUntilRun = new Date(row.nextScheduledAt).getTime() - now;
        if (millisecondsUntilRun <= 0) {
            return 'Due now';
        }

        return `In ${this.formatDuration(millisecondsUntilRun)}`;
    }

    timelineClass(row) {
        const classes = ['timeline-item'];

        if (row.status === 'Disabled') {
            classes.push('timeline-disabled');
        }

        if (row.hasError) {
            classes.push('timeline-error');
        }

        return classes.join(' ');
    }

    statusClass(status) {
        const variant = {
            'Due Now': 'due',
            Disabled: 'disabled',
            Scheduled: 'scheduled'
        }[status] || 'scheduled';

        return `status-pill status-${variant}`;
    }

    formatDuration(milliseconds) {
        const totalMinutes = Math.max(1, Math.ceil(milliseconds / 60000));
        const days = Math.floor(totalMinutes / 1440);
        const hours = Math.floor((totalMinutes % 1440) / 60);
        const minutes = totalMinutes % 60;

        if (days > 0) {
            return `${days}d${hours > 0 ? ` ${hours}h` : ''}`;
        }

        if (hours > 0) {
            return `${hours}h${minutes > 0 ? ` ${minutes}m` : ''}`;
        }

        return `${minutes}m`;
    }

    startOfToday() {
        const now = new Date();
        return new Date(now.getFullYear(), now.getMonth(), now.getDate());
    }

    addDays(date, days) {
        return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days);
    }

    formatSectionDate(date) {
        return new Intl.DateTimeFormat(undefined, {
            weekday: 'short',
            month: 'short',
            day: 'numeric'
        }).format(date);
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
