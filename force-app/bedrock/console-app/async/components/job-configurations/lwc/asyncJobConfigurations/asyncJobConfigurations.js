import { LightningElement } from "lwc";
import getJobConfigurations from "@salesforce/apex/AsyncJobConfigurationsController.getJobConfigurations";

const COLUMNS = [
    {
        label: "Open",
        type: "button",
        initialWidth: 90,
        typeAttributes: {
            label: "Open",
            name: "open",
            title: "Open async job metadata",
            variant: "base"
        }
    },
    { label: "Developer Name", fieldName: "developerName" },
    { label: "Label", fieldName: "label" },
    { label: "Apex Class", fieldName: "apexClass" },
    {
        label: "Batch Size",
        fieldName: "batchSize",
        type: "number",
        initialWidth: 130
    }
];

export default class AsyncJobConfigurations extends LightningElement {
    columns = COLUMNS;
    rows = [];
    isLoading = false;
    errorMessage;

    connectedCallback() {
        this.loadJobConfigurations();
    }

    get recordCountLabel() {
        const count = this.rows.length;
        return `${count} ${count === 1 ? "record" : "records"}`;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    handleRowAction(event) {
        const { action, row } = event.detail;

        if (action.name === "open") {
            window.open(
                `/lightning/setup/CustomMetadata/page?address=%2f${row.id}`,
                "_blank",
                "noopener"
            );
        }
    }

    async loadJobConfigurations() {
        this.isLoading = true;
        this.errorMessage = undefined;

        try {
            this.rows = await getJobConfigurations();
        } catch (error) {
            this.rows = [];
            this.errorMessage = this.reduceErrors(error);
        } finally {
            this.isLoading = false;
        }
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((entry) => entry.message).join(", ");
        }

        return (
            error?.body?.message ||
            error?.message ||
            "Unable to load async jobs."
        );
    }
}
