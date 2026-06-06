import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const [libraryName, ...deployArguments] = process.argv.slice(2);

if (!libraryName || libraryName === '--help' || libraryName === '-h') {
  console.error('Usage: npm run deploy -- <library-name-or-path> [additional sf deploy args]');
  console.error('Example: npm run deploy -- async --dry-run');
  process.exit(libraryName ? 0 : 1);
}

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
