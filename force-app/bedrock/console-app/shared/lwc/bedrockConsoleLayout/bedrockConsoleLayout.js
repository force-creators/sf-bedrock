import { api, LightningElement } from 'lwc';

export default class BedrockConsoleLayout extends LightningElement {
    @api eyebrow;
    @api heading;
    @api description;
    @api errorMessage;
    @api metrics = [];

    get hasError() {
        return Boolean(this.errorMessage);
    }
}
