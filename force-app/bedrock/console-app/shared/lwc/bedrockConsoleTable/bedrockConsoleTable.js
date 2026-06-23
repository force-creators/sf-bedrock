import { api, LightningElement } from "lwc";

export default class BedrockConsoleTable extends LightningElement {
    @api columns = [];
    @api countLabel = "0 records";
    @api emptyHeading;
    @api emptyIconName = "utility:info";
    @api emptyMessage;
    @api hideCheckboxColumn = false;
    @api isLoading = false;
    @api keyField = "id";
    @api refreshButtonLabel = "Refresh";
    @api rows = [];
    @api searchLabel = "Search";
    @api searchPlaceholder = "Search";
    @api searchTerm = "";
    @api selectedRows = [];
    @api showSearch = false;
    @api sortedBy;
    @api sortedDirection;

    get hasRows() {
        return this.rows?.length > 0;
    }

    get refreshButtonClass() {
        return this.isLoading
            ? "refresh-button is-refreshing"
            : "refresh-button";
    }

    handleSearchChange(event) {
        this.dispatchEvent(
            new CustomEvent("searchchange", {
                detail: { value: event.target.value }
            })
        );
    }

    handleRefresh() {
        this.dispatchEvent(new CustomEvent("refresh"));
    }

    handleSort(event) {
        this.dispatchEvent(new CustomEvent("sort", { detail: event.detail }));
    }

    handleRowSelection(event) {
        this.dispatchEvent(
            new CustomEvent("rowselection", { detail: event.detail })
        );
    }

    handleRowAction(event) {
        this.dispatchEvent(
            new CustomEvent("rowaction", { detail: event.detail })
        );
    }
}
