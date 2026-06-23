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
    label: 'Start Here',
    items: [
      { label: 'Overview', href: '/' },
      { label: 'Getting Started', href: '/getting-started' },
      { label: 'Bedrock Console', href: '/console' }
    ]
  },
  {
    label: 'Frameworks',
    items: [
      { label: 'Async', href: '/async' },
      { label: 'EventRelay', href: '/event-relay' },
      { label: 'Scheduler', href: '/scheduler' },
      { label: 'REST', href: '/rest' },
      { label: 'Data', href: '#', status: 'Roadmap' }
    ]
  },
  {
    label: 'Tools',
    items: [
      { label: 'TestData', href: '/test-data' },
      { label: 'DML', href: '/dml' },
      { label: 'Query', href: '/query' },
      { label: 'Selector', href: '/selector' },
      { label: 'TriggerHandler', href: '/trigger-handler' },
      { label: 'RecordBuffer', href: '/record-buffer' },
      { label: 'Generic', href: '/generic' },
      { label: 'FeatureFlag', href: '/feature-flag' },
      { label: 'PlatformCache', href: '/platform-cache' },
      { label: 'Limiter', href: '/limiter' },
      { label: 'Pluck', href: '/pluck' }
    ]
  }
];
