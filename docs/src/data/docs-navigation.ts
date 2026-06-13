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
      { label: 'Getting Started', href: '/getting-started' },
      { label: 'Bedrock Console', href: '/console' }
    ]
  },
  {
    label: 'Async Services',
    items: [
      { label: 'Async', href: '/async' },
      { label: 'Scheduler', href: '/scheduler' },
      { label: 'Event', href: '#', status: 'Roadmap' }
    ]
  },
  {
    label: 'Foundation',
    items: [
      { label: 'TestData', href: '/test-data' },
      { label: 'Generic', href: '/generic' },
      { label: 'FeatureFlag', href: '/feature-flag' },
      { label: 'PlatformCache', href: '/platform-cache' }
    ]
  },
  {
    label: 'Automation',
    items: [
      { label: 'TriggerHandler', href: '/trigger-handler' },
      { label: 'RecordBuffer', href: '/record-buffer' }
    ]
  },
  {
    label: 'Dependency Injection',
    items: [
      { label: 'DML', href: '/dml' },
      { label: 'Query', href: '/query' }
    ]
  },
  {
    label: 'Other',
    items: [
      { label: 'Limiter', href: '/limiter' },
      { label: 'Pluck', href: '/pluck' }
    ]
  }
];
