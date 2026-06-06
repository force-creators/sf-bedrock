export interface NavItem {
  label: string;
  href: string;
  status?: string;
}

export interface NavGroup {
  label: string;
  items: NavItem[];
}

export interface SectionLink {
  label: string;
  href: string;
}

export const navGroups: NavGroup[] = [
  {
    label: 'Start',
    items: [
      { label: 'Overview', href: '/' },
      { label: 'Getting Started', href: '/getting-started' }
    ]
  },
  {
    label: 'Async Services',
    items: [
      { label: 'Async', href: '#', status: 'Roadmap' },
      { label: 'Event', href: '#', status: 'Roadmap' },
      { label: 'Scheduler', href: '#', status: 'Roadmap' }
    ]
  },
  {
    label: 'Foundation',
    items: [
      { label: 'TestData', href: '/test-data' },
      { label: 'Generic', href: '#', status: 'Draft' },
      { label: 'FeatureFlag', href: '#', status: 'Draft' }
    ]
  },
  {
    label: 'Automation',
    items: [
      { label: 'TriggerHandler', href: '#', status: 'Draft' },
      { label: 'RecordBuffer', href: '#', status: 'Draft' }
    ]
  },
  {
    label: 'Dependency Injection',
    items: [
      { label: 'DML', href: '#', status: 'Draft' },
      { label: 'Query', href: '#', status: 'Draft' }
    ]
  }
];
