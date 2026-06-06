import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const scriptArguments = process.argv.slice(2);

if (scriptArguments[0] === '--help' || scriptArguments[0] === '-h') {
  console.error('Usage: npm run deploy [-- <library-name-or-path>] [additional sf deploy args]');
  console.error('Examples:');
  console.error('  npm run deploy');
  console.error('  npm run deploy -- async --dry-run');
  console.error('  npm run deploy -- --dry-run');
  process.exit(0);
}

const hasDeployTarget = Boolean(scriptArguments[0]) && !scriptArguments[0].startsWith('-');

if (!hasDeployTarget) {
  const commandArguments = [
    'project',
    'deploy',
    'start',
    '--target-org',
    'sf-bedrock',
    ...scriptArguments,
  ];

  console.log(`Running: sf ${commandArguments.join(' ')}`);

  const result = spawnSync('sf', commandArguments, { stdio: 'inherit' });

  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }

  process.exit(result.status ?? 1);
}

const [libraryName, ...deployArguments] = scriptArguments;

const candidatePaths = [
  libraryName,
  `force-app/bedrock/lib/${libraryName}`,
];

const sourceDir = candidatePaths
  .map((candidatePath) => resolve(candidatePath))
  .find((candidatePath) => existsSync(candidatePath));

if (!sourceDir) {
  console.error(`Could not find a deploy target for "${libraryName}".`);
  console.error('Checked:');
  candidatePaths.forEach((candidatePath) => console.error(`- ${candidatePath}`));
  process.exit(1);
}

const commandArguments = [
  'project',
  'deploy',
  'start',
  '--source-dir',
  sourceDir,
  '--target-org',
  'sf-bedrock',
  ...deployArguments,
];

console.log(`Running: sf ${commandArguments.join(' ')}`);

const result = spawnSync('sf', commandArguments, { stdio: 'inherit' });

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);
