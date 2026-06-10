import { LightningElement } from 'lwc';

export default class AsyncLayout extends LightningElement {
    selectedId = 'dashboard';

    handleTabActive(event) {
        this.selectedId = event.target.value;
    }
}
