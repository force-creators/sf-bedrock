import { LightningElement, api } from "lwc";
import getBacklog from "@salesforce/apex/AsyncBacklogController.getBacklog";

const COLUMNS = [
    { label: "Thread / Job", fieldName: "threadLabel", initialWidth: 220 },
    { label: "Running User", fieldName: "runningUser" },
    { label: "Apex Class", fieldName: "apexClass" },
    {
        label: "Priority",
        fieldName: "priority",
        type: "number",
        initialWidth: 110
    },
    { label: "Record Id", fieldName: "recordId" },
    { label: "Status", fieldName: "status", initialWidth: 130 },
    {
        label: "Created Date",
        fieldName: "createdDate",
        type: "date",
        initialWidth: 180
    }
];

export default class AsyncBacklog extends LightningElement {
    columns = COLUMNS;
    treeRows = [];
    expandedRows = [];
    isLoading = false;
    errorMessage;

    connectedCallback() {
        this.loadBacklog();
    }

    get recordCountLabel() {
        const count = this.treeRows.reduce(
            (total, group) => total + group._children.length,
            0
        );
        return `${count} ${count === 1 ? "record" : "records"}`;
    }

    get refreshButtonClass() {
        return this.isLoading
            ? "refresh-button is-refreshing"
            : "refresh-button";
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

    @api
    refresh() {
        this.loadBacklog();
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
            this.isLoading = false;
            this.dispatchCountChange();
        }
    }

    dispatchCountChange() {
        const count = this.treeRows.reduce(
            (total, group) => total + group._children.length,
            0
        );
        this.dispatchEvent(
            new CustomEvent("countchange", {
                detail: { count }
            })
        );
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(", ");
        }

        return (
            error?.body?.message ||
            error?.message ||
            "Unable to load the async backlog."
        );
    }
}
