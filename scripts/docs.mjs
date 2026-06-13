import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

const scriptArguments = process.argv.slice(2);
const docsDirectory = resolve('docs');
const localUrlPattern = /(https?:\/\/(127\.0\.0\.1|localhost):\d+\/)/;
const tunnelUrlPattern = /(https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com)/;
const docsHost = '127.0.0.1';
const docsPort = '4321';

function openBrowser(url) {
  if (process.platform === 'darwin') {
    return spawn('open', [url], { stdio: 'ignore', detached: true });
  }

  if (process.platform === 'win32') {
    return spawn('cmd', ['/c', 'start', '', url], { stdio: 'ignore', detached: true });
  }

  return spawn('xdg-open', [url], { stdio: 'ignore', detached: true });
}

function runNpm(commandArguments) {
  const result = spawnSync('npm', commandArguments, {
    cwd: docsDirectory,
    stdio: 'inherit',
  });

  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }

  if ((result.status ?? 1) !== 0) {
    process.exit(result.status ?? 1);
  }
}

function ensureDocsDirectory() {
  if (!existsSync(docsDirectory)) {
    console.error('Could not find the docs project at "docs/".');
    process.exit(1);
  }
}

function runBuild(buildArguments) {
  const commandArguments = ['run', 'build'];

  if (buildArguments.length > 0) {
    commandArguments.push('--', ...buildArguments);
  }

  console.log(`Running in ${docsDirectory}: npm ${commandArguments.join(' ')}`);
  runNpm(commandArguments);
}

function runDeploy(deployArguments) {
  const packageJsonPath = resolve(docsDirectory, 'package.json');

  if (!existsSync(packageJsonPath)) {
    console.error(`Could not find a package.json in "${docsDirectory}".`);
    process.exit(1);
  }

  let packageJson;

  try {
    packageJson = JSON.parse(readFileSync(packageJsonPath, 'utf8'));
  } catch (error) {
    const parseErrorMessage = error instanceof Error ? error.message : String(error);
    console.error(`Could not parse docs package.json: ${parseErrorMessage}`);
    process.exit(1);
  }

  if (!packageJson.scripts || !packageJson.scripts.deploy) {
    console.error(`No "deploy" script is configured in ${packageJsonPath}.`);
    console.error('Add a deploy script to your docs project package.json and try again.');
    process.exit(1);
  }

  runBuild([]);

  const commandArguments = ['run', 'deploy'];

  if (deployArguments.length > 0) {
    commandArguments.push('--', ...deployArguments);
  }

  console.log(`Running in ${docsDirectory}: npm ${commandArguments.join(' ')}`);
  runNpm(commandArguments);
}

function runDev(devArguments) {
  const cloudflaredCheck = spawnSync('cloudflared', ['--version'], {
    stdio: 'ignore',
  });

  if (cloudflaredCheck.error || (cloudflaredCheck.status ?? 1) !== 0) {
    console.error('Could not find the Cloudflare Tunnel client "cloudflared".');
    console.error('Install it with: brew install cloudflared');
    console.error('Then rerun: npm run docs');
    process.exit(1);
  }

  runBuild([]);

  const commandArguments = ['run', 'dev', '--', '--host', docsHost, '--port', docsPort];

  if (devArguments.length > 0) {
    commandArguments.push(...devArguments);
  }

  console.log(`Running in ${docsDirectory}: npm ${commandArguments.join(' ')}`);

  const devServer = spawn('npm', commandArguments, {
    cwd: docsDirectory,
    stdio: ['inherit', 'pipe', 'pipe'],
  });

  let tunnelProcess;
  let browserOpened = false;

  function stopProcesses(signal) {
    if (tunnelProcess && !tunnelProcess.killed) {
      tunnelProcess.kill(signal);
    }

    if (!devServer.killed) {
      devServer.kill(signal);
    }
  }

  function relayTunnelOutput(output, writer) {
    writer.write(output);

    if (browserOpened) {
      return;
    }

    const tunnelUrlMatch = output.match(tunnelUrlPattern);

    if (!tunnelUrlMatch) {
      return;
    }

    browserOpened = true;

    console.log(`Opening Cloudflare Tunnel URL: ${tunnelUrlMatch[1]}`);

    const browserProcess = openBrowser(tunnelUrlMatch[1]);
    browserProcess.unref();
  }

  function startTunnel(localUrl) {
    if (tunnelProcess) {
      return;
    }

    console.log(`Starting Cloudflare Tunnel for ${localUrl}`);

    tunnelProcess = spawn('cloudflared', ['tunnel', '--url', localUrl], {
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    tunnelProcess.stdout.on('data', (chunk) => relayTunnelOutput(chunk.toString(), process.stdout));
    tunnelProcess.stderr.on('data', (chunk) => relayTunnelOutput(chunk.toString(), process.stderr));

    tunnelProcess.on('error', (error) => {
      console.error(error.message);
      stopProcesses('SIGTERM');
      process.exit(1);
    });

    tunnelProcess.on('exit', (code, signal) => {
      if (code === 0 || signal) {
        return;
      }

      console.error(`Cloudflare Tunnel exited with code ${code}.`);
      stopProcesses('SIGTERM');
      process.exit(code ?? 1);
    });
  }

  function relayOutput(output, writer) {
    writer.write(output);

    const localUrlMatch = output.match(localUrlPattern);

    if (!localUrlMatch) {
      return;
    }

    startTunnel(localUrlMatch[1]);
  }

  devServer.stdout.on('data', (chunk) => relayOutput(chunk.toString(), process.stdout));
  devServer.stderr.on('data', (chunk) => relayOutput(chunk.toString(), process.stderr));

  devServer.on('error', (error) => {
    console.error(error.message);
    process.exit(1);
  });

  devServer.on('exit', (code) => {
    if (tunnelProcess && !tunnelProcess.killed) {
      tunnelProcess.kill('SIGTERM');
    }

    process.exit(code ?? 1);
  });

  process.on('SIGINT', () => {
    stopProcesses('SIGINT');
  });

  process.on('SIGTERM', () => {
    stopProcesses('SIGTERM');
  });
}

if (scriptArguments[0] === '--help' || scriptArguments[0] === '-h') {
  console.error('Usage:');
  console.error('  npm run docs [-- <additional Astro dev args>]');
  console.error('  npm run docs:build [-- <additional Astro build args>]');
  console.error('  npm run docs:deploy [-- <additional deploy args>]');
  process.exit(0);
}

ensureDocsDirectory();

const mode = scriptArguments[0] === 'build' || scriptArguments[0] === 'deploy' || scriptArguments[0] === 'dev'
  ? scriptArguments[0]
  : 'dev';

const modeArguments = mode === 'dev' && scriptArguments[0] !== 'dev'
  ? scriptArguments
  : scriptArguments.slice(1);

if (mode === 'build') {
  runBuild(modeArguments);
} else if (mode === 'deploy') {
  runDeploy(modeArguments);
} else {
  runDev(modeArguments);
}
