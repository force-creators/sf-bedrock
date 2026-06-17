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
      { label: 'Threading Model', href: '/threading-model' }
    ]
  },
  {
    label: 'Adoption',
    items: [
      { label: 'Why Bedrock', href: '/why-bedrock' },
      { label: 'Adoption Playbook', href: '/adoption-playbook' },
      { label: 'Enterprise Readiness', href: '/enterprise-readiness' },
      { label: 'Common Apex Patterns', href: '/compare-architecture-patterns' }
    ]
  },
  {
    label: 'Operations',
    items: [
      { label: 'Admin Setup & Operations', href: '/admin-setup-operations' },
      { label: 'Bedrock Console', href: '/console' }
    ]
  },
  {
    label: 'Frameworks',
    items: [
      { label: 'Async', href: '/async' },
      { label: 'Event', href: '#', status: 'Roadmap' },
      { label: 'Scheduler', href: '/scheduler' },
      { label: 'REST', href: '#', status: 'Roadmap' },
      { label: 'Data', href: '#', status: 'Roadmap' }
    ]
  },
  {
    label: 'Tools',
    items: [
      { label: 'TestData', href: '/test-data' },
      { label: 'DML', href: '/dml' },
      { label: 'Query', href: '/query' },
      { label: 'Selector', href: '#', status: 'Roadmap' },
      { label: 'TriggerHandler', href: '/trigger-handler' },
      { label: 'RecordBuffer', href: '/record-buffer' },
      { label: 'Thread', href: '/thread' },
      { label: 'Generic', href: '/generic' },
      { label: 'FeatureFlag', href: '/feature-flag' },
      { label: 'PlatformCache', href: '/platform-cache' },
      { label: 'Limiter', href: '/limiter' },
      { label: 'Pluck', href: '/pluck' }
    ]
  }
];
