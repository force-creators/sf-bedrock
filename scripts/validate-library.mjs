import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

function collectApexClassFiles(startDirectory) {
  const files = [];
  const entries = readdirSync(startDirectory, { withFileTypes: true });

  for (const entry of entries) {
    const entryPath = resolve(startDirectory, entry.name);

    if (entry.isDirectory()) {
      files.push(...collectApexClassFiles(entryPath));
      continue;
    }

    if (entry.isFile() && entry.name.endsWith('.cls')) {
      files.push(entryPath);
    }
  }

  return files;
}

function isTestClass(filePath) {
  const source = readFileSync(filePath, 'utf8');
  return /@istest\b/i.test(source);
}

function classNameFromFile(filePath) {
  return basename(filePath, '.cls');
}

function hasWaitArgument(argumentsToCheck) {
  return argumentsToCheck.some((argument) => argument === '--wait' || argument === '-w' || argument.startsWith('--wait='));
}

const [libraryName, ...runArguments] = process.argv.slice(2);

if (libraryName === '--help' || libraryName === '-h') {
  console.error('Usage: npm run validate [-- <library-name-or-path> [additional sf apex args]]');
  console.error('Examples:');
  console.error('  npm run validate');
  console.error('  npm run validate -- feature-flag');
  console.error('  npm run validate -- force-app/bedrock/lib/query --wait 20');
  process.exit(0);
}

if (!libraryName) {
  const commandArguments = ['apex', 'run', 'test', '--test-level', 'RunLocalTests', '--wait', '10'];

  console.log(`Running: sf ${commandArguments.join(' ')}`);

  const result = spawnSync('sf', commandArguments, { stdio: 'inherit' });

  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }

  process.exit(result.status ?? 1);
}

const candidatePaths = [
  libraryName,
  `force-app/bedrock/lib/${libraryName}`,
];

const sourceDirectory = candidatePaths
  .map((candidatePath) => resolve(candidatePath))
  .find((candidatePath) => existsSync(candidatePath));

if (!sourceDirectory) {
  console.error(`Could not find a validation target for "${libraryName}".`);
  console.error('Checked:');
  candidatePaths.forEach((candidatePath) => console.error(`- ${candidatePath}`));
  process.exit(1);
}

const apexClassFiles = collectApexClassFiles(sourceDirectory);
const testClassNames = apexClassFiles
  .filter((filePath) => isTestClass(filePath))
  .map((filePath) => classNameFromFile(filePath));

if (testClassNames.length === 0) {
  console.error(`No Apex test classes were found in "${sourceDirectory}".`);
  process.exit(1);
}

const commandArguments = ['apex', 'run', 'test', '--test-level', 'RunSpecifiedTests'];

for (const testClassName of testClassNames) {
  commandArguments.push('--class-names', testClassName);
}

if (!hasWaitArgument(runArguments)) {
  commandArguments.push('--wait', '10');
}

commandArguments.push(...runArguments);

console.log(`Running: sf ${commandArguments.join(' ')}`);

const result = spawnSync('sf', commandArguments, { stdio: 'inherit' });

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);
