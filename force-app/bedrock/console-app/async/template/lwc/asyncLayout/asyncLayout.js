import { LightningElement } from 'lwc';

const MENU_ITEMS = [
    {
        id: 'dashboard',
        label: 'Dashboard',
        iconName: 'utility:dashboard'
    },
    {
        id: 'backlog',
        label: 'Backlog',
        iconName: 'utility:queue'
    },
    {
        id: 'errors',
        label: 'Errors',
        iconName: 'utility:error'
    },
    {
        id: 'performance',
        label: 'Performance',
        iconName: 'utility:speedometer'
    },
    {
        id: 'job-configurations',
        label: 'Job Configurations',
        iconName: 'utility:settings'
    },
    {
        id: 'settings',
        label: 'Settings',
        iconName: 'utility:setup'
    }
];

export default class AsyncLayout extends LightningElement {
    selectedId = 'dashboard';

    get menuItems() {
        return MENU_ITEMS.map((item) => {
            const isSelected = item.id === this.selectedId;

            return {
                ...item,
                ariaCurrent: isSelected ? 'page' : null,
                className: isSelected ? 'menu-item menu-item-selected' : 'menu-item'
            };
        });
    }

    handleMenuSelect(event) {
        this.selectedId = event.currentTarget.dataset.id;
    }

    get isDashboardSelected() {
        return this.selectedId === 'dashboard';
    }

    get isBacklogSelected() {
        return this.selectedId === 'backlog';
    }

    get isErrorsSelected() {
        return this.selectedId === 'errors';
    }

    get isPerformanceSelected() {
        return this.selectedId === 'performance';
    }

    get isJobConfigurationsSelected() {
        return this.selectedId === 'job-configurations';
    }

    get isSettingsSelected() {
        return this.selectedId === 'settings';
    }
}
