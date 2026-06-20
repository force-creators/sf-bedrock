import { api, LightningElement } from 'lwc';

export default class BedrockSectionHeader extends LightningElement {
    @api heading;
    @api description;
    @api isLoading = false;
    @api loadingAlternativeText = 'Loading';
}
