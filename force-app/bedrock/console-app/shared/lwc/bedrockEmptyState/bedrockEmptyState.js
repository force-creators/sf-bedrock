import { api, LightningElement } from "lwc";

export default class BedrockEmptyState extends LightningElement {
    @api iconName = "utility:info";
    @api heading;
    @api message;
}
