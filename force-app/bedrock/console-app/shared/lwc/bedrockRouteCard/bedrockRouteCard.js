import { api, LightningElement } from "lwc";

export default class BedrockRouteCard extends LightningElement {
    @api accent = "blue";
    @api badges = [];
    @api expanded = false;
    @api expandable = false;
    @api iconName = "utility:route";
    @api label;
    @api routeKey;
    @api cardTitle;

    get cardClass() {
        return `route-card route-card-${this.accent || "blue"}`;
    }

    get isExpandable() {
        return this.expandable === true || this.expandable === "true";
    }

    get showBody() {
        return (
            !this.isExpandable ||
            this.expanded === true ||
            this.expanded === "true"
        );
    }

    get toggleIconName() {
        return this.showBody ? "utility:chevrondown" : "utility:chevronright";
    }

    get toggleAlternativeText() {
        return this.showBody
            ? "Collapse route details"
            : "Expand route details";
    }

    get toggleTitle() {
        return this.toggleAlternativeText;
    }

    handleToggle() {
        this.dispatchEvent(
            new CustomEvent("toggle", { detail: { routeKey: this.routeKey } })
        );
    }
}
