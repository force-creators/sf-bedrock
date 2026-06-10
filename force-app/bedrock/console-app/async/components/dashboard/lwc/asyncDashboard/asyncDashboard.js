import { LightningElement } from 'lwc';

const METRICS = [
    { id: 'primary', label: 'Primary signal', value: 'Ready' },
    { id: 'secondary', label: 'Records', value: '0' },
    { id: 'tertiary', label: 'Attention', value: 'None' }
];

export default class AsyncDashboard extends LightningElement {
    metrics = METRICS;
}
