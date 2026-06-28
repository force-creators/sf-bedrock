#!/usr/bin/env node
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const DEFAULTS = {
  org: 'sf-bedrock',
  routeCount: 50,
  batchSize: 200,
  lowThreads: 1,
  highThreads: 50,
  phaseOneAsync: 10000,
  phaseOneEvents: 10000,
  phaseThreeAsync: 20000,
  phaseThreeEvents: 20000,
  concurrency: 4,
  pollSeconds: 10,
  drainTimeoutSeconds: 900,
  repeat: 1,
};

const API_VERSION = '67.0';
const ASYNC_CLASS = 'BedrockNukeAsync';
const EVENT_PUBLISHER = 'BedrockNukeEventPublisher';
const EVENT_ROUTE_PREFIX = 'BedrockNukePublish';
const EVENT_ROUTING_KEY = 'NukeRoute';
const RESULTS_DIR = resolve('scripts/nuke/results');

const options = parseArguments(process.argv.slice(2));

if (options.help) {
  printHelp();
  process.exit(0);
}

await main();

async function main() {
  mkdirSync(RESULTS_DIR, { recursive: true });

  const context = await buildContext();
  if (options.command === 'deploy') {
    deployAdapters();
    return;
  }
  if (options.command === 'cleanup') {
    await cleanup(context);
    return;
  }
  if (options.command === 'observe') {
    console.log(JSON.stringify(await collectStats(context), null, 2));
    return;
  }

  deployAdapters();

  for (let run = 1; run <= options.repeat; run++) {
    console.log(`\n=== NUKE RUN ${run}/${options.repeat} ===`);
    await cleanup(context);
    await setThreads(context, options.lowThreads);
    await createAlternatingLoad(context, {
      label: 'low-thread backlog',
      asyncCount: options.phaseOneAsync,
      eventCount: options.phaseOneEvents,
      asyncOffset: run * 1000000,
      eventOffset: run * 2000000,
      concurrency: options.concurrency,
    });
    await snapshot(context, `run-${run}-after-low-thread-create`);

    await setThreads(context, options.highThreads);
    await enqueueAsyncBatch(context, run * 3000000, 1, 'high-thread-kick-async');
    await publishEventBatch(context, run * 4000000, 1, 'high-thread-kick-event');
    await waitForDrain(context, `run ${run} low-thread backlog after high-thread kick`);

    await createAlternatingLoad(context, {
      label: 'high-thread concurrency',
      asyncCount: options.phaseThreeAsync,
      eventCount: options.phaseThreeEvents,
      asyncOffset: run * 5000000,
      eventOffset: run * 6000000,
      concurrency: options.concurrency,
    });
    await waitForDrain(context, `run ${run} high-thread concurrency`);
    await snapshot(context, `run-${run}-final`);
  }
}

function parseArguments(args) {
  const parsed = { ...DEFAULTS, command: 'run' };
  const commands = new Set(['run', 'deploy', 'cleanup', 'observe']);

  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (commands.has(arg)) {
      parsed.command = arg;
      continue;
    }
    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
      continue;
    }
    if (!arg.startsWith('--')) {
      throw new Error(`Unknown argument "${arg}".`);
    }

    const [rawKey, inlineValue] = arg.slice(2).split('=');
    const key = rawKey.replace(/-([a-z])/g, (_, char) => char.toUpperCase());
    const value = inlineValue ?? args[++index];
    if (value === undefined) {
      throw new Error(`Missing value for --${rawKey}.`);
    }

    if (key === 'org') {
      parsed.org = value;
    } else if (key in DEFAULTS) {
      parsed[key] = Number(value);
    } else {
      throw new Error(`Unknown option --${rawKey}.`);
    }
  }

  return parsed;
}

function printHelp() {
  console.log(`Usage:
  node scripts/nuke/nuke.mjs run [options]
  node scripts/nuke/nuke.mjs deploy [--org sf-bedrock]
  node scripts/nuke/nuke.mjs cleanup [--org sf-bedrock]
  node scripts/nuke/nuke.mjs observe [--org sf-bedrock]

Options:
  --org <alias>                    Target org alias. Default: sf-bedrock
  --low-threads <n>                Thread cap for backlog creation. Default: 1
  --high-threads <n>               Thread cap for drain/concurrency. Default: 50
  --phase-one-async <n>            Async rows for low-thread phase. Default: 10000
  --phase-one-events <n>           Event rows for low-thread phase. Default: 10000
  --phase-three-async <n>          Async rows for high-thread phase. Default: 20000
  --phase-three-events <n>         Event rows for high-thread phase. Default: 20000
  --batch-size <n>                 Creation batch size. Default: 200
  --route-count <n>                EventRelay publish route lanes. Default: 50
  --concurrency <n>                Concurrent executeAnonymous requests. Default: 4
  --repeat <n>                     Run the full nuke multiple times. Default: 1
  --drain-timeout-seconds <n>      Drain wait timeout per phase. Default: 900
  --poll-seconds <n>               Observation polling interval. Default: 10
`);
}

async function buildContext() {
  const display = sfJson([
    'org',
    'display',
    '--target-org',
    options.org,
    '--json',
  ]).result;
  const token = sfJson([
    'org',
    'auth',
    'show-access-token',
    '--target-org',
    options.org,
    '--json',
  ]).result.accessToken;

  return {
    org: options.org,
    instanceUrl: display.instanceUrl,
    accessToken: token,
    apiVersion: display.apiVersion || API_VERSION,
  };
}

function deployAdapters() {
  const tempSource = resolve(
    '.sf',
    `sf-bedrock-nuke-${process.pid}-${Date.now()}`
  );
  try {
    const metadataDir = join(tempSource, 'customMetadata');
    mkdirSync(metadataDir, { recursive: true });
    writeFileSync(
      join(metadataDir, 'Async_Job.BedrockNukeAsync.md-meta.xml'),
      asyncJobMetadata(),
      'utf8'
    );
    for (let index = 0; index < options.routeCount; index++) {
      writeFileSync(
        join(
          metadataDir,
          `Event_Config.${eventRouteName(index)}.md-meta.xml`
        ),
        eventRouteMetadata(index),
        'utf8'
      );
    }

    sfJson([
      'project',
      'deploy',
      'start',
      '--target-org',
      options.org,
      '--source-dir',
      'scripts/nuke/source/classes',
      '--source-dir',
      tempSource,
      '--test-level',
      'NoTestRun',
      '--wait',
      '10',
      '--json',
    ]);
    console.log(`Deployed nuke adapters and ${options.routeCount} EventRelay routes.`);
  } finally {
    rmSync(tempSource, { recursive: true, force: true });
  }
}

function asyncJobMetadata() {
  return `<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>Bedrock Nuke Async</label>
    <protected>false</protected>
    <values><field>Apex__c</field><value xsi:type="xsd:string">${ASYNC_CLASS}</value></values>
    <values><field>Batch_Size__c</field><value xsi:type="xsd:double">${options.batchSize}</value></values>
    <values><field>Max_Retries__c</field><value xsi:type="xsd:double">0</value></values>
    <values><field>Priority__c</field><value xsi:type="xsd:double">1</value></values>
</CustomMetadata>
`;
}

function eventRouteMetadata(index) {
  return `<?xml version="1.0" encoding="UTF-8" ?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>${eventRouteName(index)}</label>
    <protected>false</protected>
    <values><field>Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Direction__c</field><value xsi:type="xsd:string">Publish</value></values>
    <values><field>Source_Type__c</field><value xsi:type="xsd:string">Generic</value></values>
    <values><field>Routing_Key__c</field><value xsi:type="xsd:string">${EVENT_ROUTING_KEY}</value></values>
    <values><field>Routing_Value__c</field><value xsi:type="xsd:string">${eventRouteName(index)}</value></values>
    <values><field>Apex__c</field><value xsi:type="xsd:string">${EVENT_PUBLISHER}</value></values>
    <values><field>Batch_Size__c</field><value xsi:type="xsd:double">${options.batchSize}</value></values>
    <values><field>Max_Retries__c</field><value xsi:type="xsd:double">0</value></values>
</CustomMetadata>
`;
}

async function cleanup(context) {
  console.log('Cleaning previous nuke runtime rows...');
  await cleanupObject(context, 'Async__c', `Apex__c = '${ASYNC_CLASS}'`);
  await cleanupObject(context, 'Event__c', `Route__c LIKE '${EVENT_ROUTE_PREFIX}%'`);
  await cleanupObject(context, 'Thread__c', `Thread_Key__c LIKE '${EVENT_ROUTE_PREFIX}%'`);
  await cleanupDanglingNukeAsyncThreads(context);
  await snapshot(context, 'after-cleanup');
}

async function cleanupObject(context, objectName, whereClause) {
  while (true) {
    const count = await countWhere(context, objectName, whereClause);
    if (count === 0) {
      return;
    }
    const apex = `List<${objectName}> rows = [SELECT Id FROM ${objectName} WHERE ${whereClause} LIMIT 10000]; delete rows;`;
    await executeAnonymous(context, apex, `cleanup ${objectName}`, { retries: 5 });
  }
}

async function cleanupDanglingNukeAsyncThreads(context) {
  const apex = `
Set<Id> activeThreadIds = new Set<Id>();
for (Async__c workItem : [SELECT Thread__c FROM Async__c WHERE Thread__c != null]) {
    activeThreadIds.add(workItem.Thread__c);
}
List<Thread__c> threads = new List<Thread__c>();
for (Thread__c threadRecord : [SELECT Id FROM Thread__c WHERE Pool__c = 'Async' LIMIT 10000]) {
    if (!activeThreadIds.contains(threadRecord.Id)) {
        threads.add(threadRecord);
    }
}
delete threads;
`;
  await executeAnonymous(context, apex, 'cleanup dangling async threads', {
    retries: 5,
  });
}

async function setThreads(context, value) {
  const apex = `
Thread_Settings__c threadSettings = Thread_Settings__c.getOrgDefaults();
if (threadSettings == null) {
    threadSettings = new Thread_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
}
threadSettings.Max_Threads__c = ${value};
upsert threadSettings;

Async_Settings__c asyncSettings = Async_Settings__c.getOrgDefaults();
if (asyncSettings == null) {
    asyncSettings = new Async_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
}
asyncSettings.Max_Threads__c = ${value};
upsert asyncSettings;
`;
  await executeAnonymous(context, apex, `set threads ${value}`, { retries: 5 });
  console.log(`Set Thread_Settings__c.Max_Threads__c to ${value}.`);
}

async function createAlternatingLoad(
  context,
  { label, asyncCount, eventCount, asyncOffset, eventOffset, concurrency }
) {
  console.log(
    `Creating ${label}: ${asyncCount} Async + ${eventCount} EventRelay publish work, ${options.batchSize}/request, concurrency ${concurrency}.`
  );

  const requests = [];
  const asyncBatches = Math.ceil(asyncCount / options.batchSize);
  const eventBatches = Math.ceil(eventCount / options.batchSize);
  const totalBatches = Math.max(asyncBatches, eventBatches);

  for (let batch = 0; batch < totalBatches; batch++) {
    if (batch < asyncBatches) {
      const start = asyncOffset + batch * options.batchSize;
      const count = Math.min(options.batchSize, asyncCount - batch * options.batchSize);
      requests.push({
        type: 'async',
        run: () => enqueueAsyncBatch(context, start, count, `${label} async ${batch + 1}/${asyncBatches}`),
      });
    }
    if (batch < eventBatches) {
      const start = eventOffset + batch * options.batchSize;
      const count = Math.min(options.batchSize, eventCount - batch * options.batchSize);
      requests.push({
        type: 'event',
        run: () => publishEventBatch(context, start, count, `${label} event ${batch + 1}/${eventBatches}`),
      });
    }
  }

  if (concurrency > 1) {
    const firstEventIndex = requests.findIndex((task) => task.type === 'event');
    if (firstEventIndex >= 0) {
      const [firstEvent] = requests.splice(firstEventIndex, 1);
      console.log(`${label}: warming EventRelay route threads with first event batch before concurrent fanout.`);
      await firstEvent.run();
    }
  }

  await runWithConcurrency(requests, concurrency, label);
  await snapshot(context, `after-${slug(label)}-create`);
}

async function enqueueAsyncBatch(context, start, count, label) {
  const apex = `
Integer startIndex = ${start};
Integer workCount = ${count};
Set<Id> recordIds = new Set<Id>();
for (Integer i = 0; i < workCount; i++) {
    String suffix = String.valueOf(startIndex + i).leftPad(12, '0');
    recordIds.add((Id) ('001' + suffix));
}
Async.enqueue(${ASYNC_CLASS}.class, recordIds);
`;
  await executeAnonymous(context, apex, label, { retries: 5 });
}

async function publishEventBatch(context, start, count, label) {
  const apex = `
Integer startIndex = ${start};
Integer workCount = ${count};
Integer routeCount = ${options.routeCount};
List<Generic> payloads = new List<Generic>();
for (Integer i = 0; i < workCount; i++) {
    Integer sequence = startIndex + i;
    Integer routeNumber = Math.mod(sequence, routeCount);
    String routeName = '${EVENT_ROUTE_PREFIX}' + String.valueOf(routeNumber).leftPad(2, '0');
    payloads.add(new Generic(new Map<String, Object>{
        '${EVENT_ROUTING_KEY}' => routeName,
        'Sequence' => sequence,
        'RunLabel' => '${escapeApexString(label)}'
    }));
}
EventRelay.publish(payloads);
`;
  await executeAnonymous(context, apex, label, { retries: 5 });
}

async function runWithConcurrency(tasks, concurrency, label) {
  let next = 0;
  let completed = 0;

  async function worker() {
    while (next < tasks.length) {
      const taskIndex = next++;
      await tasks[taskIndex].run();
      completed++;
      if (completed % 10 === 0 || completed === tasks.length) {
        console.log(`${label}: ${completed}/${tasks.length} creation requests finished.`);
      }
    }
  }

  const workers = Array.from(
    { length: Math.max(1, Math.min(concurrency, tasks.length)) },
    () => worker()
  );
  await Promise.all(workers);
}

async function waitForDrain(context, label) {
  const started = Date.now();
  const timeoutMs = options.drainTimeoutSeconds * 1000;
  let lastSignature = '';
  let stagnantPolls = 0;

  while (Date.now() - started < timeoutMs) {
    const stats = await collectStats(context);
    const active = activeWork(stats);
    const signature = JSON.stringify({
      async: stats.async,
      events: stats.events,
      threads: stats.threads,
    });
    stagnantPolls = signature === lastSignature ? stagnantPolls + 1 : 0;
    lastSignature = signature;

    console.log(
      `${label}: active=${active} async=${compactCounts(stats.async)} events=${compactCounts(stats.events)} threads=${compactThreadCounts(stats.threads)}`
    );
    await writeSnapshot(label, stats);

    if (hasHardFailures(stats)) {
      console.log(`${label}: failures/pauses detected; continuing observation until timeout or drain.`);
    }
    if (active === 0) {
      console.log(`${label}: drained successfully.`);
      return stats;
    }
    if (stagnantPolls === 6) {
      stagnantPolls = 0;
      console.log(`${label}: unchanged for six polls; waiting for scheduled stale-heartbeat recovery.`);
    }

    await sleep(options.pollSeconds * 1000);
  }

  const stats = await collectStats(context);
  await writeSnapshot(`${label}-timeout`, stats);
  throw new Error(`${label} did not drain within ${options.drainTimeoutSeconds}s.`);
}

async function snapshot(context, label) {
  const stats = await collectStats(context);
  await writeSnapshot(label, stats);
  console.log(
    `${label}: async=${compactCounts(stats.async)} events=${compactCounts(stats.events)} threads=${compactThreadCounts(stats.threads)}`
  );
  return stats;
}

async function collectStats(context) {
  const [asyncRecords, eventRecords, threadRecords, limits] = await Promise.all([
    query(context, `SELECT Status__c, COUNT(Id) total FROM Async__c WHERE Apex__c = '${ASYNC_CLASS}' GROUP BY Status__c`),
    query(context, `SELECT Status__c, COUNT(Id) total FROM Event__c WHERE Route__c LIKE '${EVENT_ROUTE_PREFIX}%' GROUP BY Status__c`),
    query(context, `SELECT Pool__c, Status__c, COUNT(Id) total FROM Thread__c GROUP BY Pool__c, Status__c`),
    rest(context, `/services/data/v${context.apiVersion}/limits/`),
  ]);

  return {
    observedAt: new Date().toISOString(),
    async: aggregateCounts(asyncRecords.records, 'Status__c'),
    events: aggregateCounts(eventRecords.records, 'Status__c'),
    threads: threadCounts(threadRecords.records),
    limits: {
      DailyAsyncApexExecutions: limits.DailyAsyncApexExecutions,
      DailyApiRequests: limits.DailyApiRequests,
      DataStorageMB: limits.DataStorageMB,
      DailyStandardVolumePlatformEvents: limits.DailyStandardVolumePlatformEvents,
    },
  };
}

function aggregateCounts(records, key) {
  const counts = {};
  for (const record of records ?? []) {
    counts[record[key] ?? 'null'] = Number(record.total ?? record.expr0 ?? 0);
  }
  return counts;
}

function threadCounts(records) {
  const counts = {};
  for (const record of records ?? []) {
    const pool = record.Pool__c ?? 'null';
    const status = record.Status__c ?? 'null';
    counts[`${pool}:${status}`] = Number(record.total ?? record.expr0 ?? 0);
  }
  return counts;
}

function activeWork(stats) {
  return (
    (stats.async.Pending ?? 0) +
    (stats.async.Running ?? 0) +
    (stats.events.Pending ?? 0) +
    (stats.events.Running ?? 0)
  );
}

function hasHardFailures(stats) {
  return (
    (stats.async.Error ?? 0) > 0 ||
    (stats.events.Error ?? 0) > 0 ||
    Object.entries(stats.threads).some(
      ([key, value]) => key.endsWith(':Paused') && value > 0
    )
  );
}

function compactCounts(counts) {
  const keys = ['Pending', 'Running', 'Done', 'Error', 'Stale'];
  return keys
    .filter((key) => counts[key])
    .map((key) => `${key}:${counts[key]}`)
    .join(',') || 'none';
}

function compactThreadCounts(counts) {
  return Object.entries(counts)
    .filter(([, value]) => value)
    .map(([key, value]) => `${key}:${value}`)
    .join(',') || 'none';
}

async function writeSnapshot(label, stats) {
  const fileName = `${new Date().toISOString().replace(/[:.]/g, '-')}-${slug(label)}.json`;
  writeFileSync(join(RESULTS_DIR, fileName), JSON.stringify(stats, null, 2), 'utf8');
}

async function countWhere(context, objectName, whereClause) {
  const result = await query(
    context,
    `SELECT COUNT(Id) total FROM ${objectName} WHERE ${whereClause}`
  );
  const record = result.records?.[0];
  return Number(record?.total ?? record?.expr0 ?? 0);
}

async function executeAnonymous(context, apex, label, { retries = 3 } = {}) {
  let attempt = 0;
  while (true) {
    attempt++;
    try {
      const encoded = encodeURIComponent(apex);
      const result = await rest(
        context,
        `/services/data/v${context.apiVersion}/tooling/executeAnonymous/?anonymousBody=${encoded}`
      );
      if (!result.compiled || !result.success) {
        throw new Error(
          [
            `${label} failed`,
            result.compileProblem && `compile: ${result.compileProblem}`,
            result.exceptionMessage && `exception: ${result.exceptionMessage}`,
            result.exceptionStackTrace && `stack: ${result.exceptionStackTrace}`,
          ]
            .filter(Boolean)
            .join('\n')
        );
      }
      return result;
    } catch (error) {
      if (attempt > retries || !isTransient(error)) {
        throw error;
      }
      const delay = Math.min(1000 * 2 ** attempt, 10000);
      console.log(`${label}: transient failure, retry ${attempt}/${retries} after ${delay}ms: ${error.message}`);
      await sleep(delay);
    }
  }
}

function isTransient(error) {
  const message = String(error?.message ?? error);
  return /UNABLE_TO_LOCK_ROW|Record Currently Unavailable|currently being modified by another user|DUPLICATE_VALUE.*Unique_Key__c|duplicate value found: Unique_Key__c|REQUEST_LIMIT_EXCEEDED|ECONNRESET|ETIMEDOUT|timeout|503|504/i.test(
    message
  );
}

async function query(context, soql) {
  return rest(
    context,
    `/services/data/v${context.apiVersion}/query/?q=${encodeURIComponent(soql)}`
  );
}

async function rest(context, path) {
  const response = await fetch(`${context.instanceUrl}${path}`, {
    headers: {
      Authorization: `Bearer ${context.accessToken}`,
      'Content-Type': 'application/json',
    },
  });
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : {};
  } catch (_) {
    body = text;
  }
  if (!response.ok) {
    throw new Error(`REST ${response.status}: ${JSON.stringify(body)}`);
  }
  return body;
}

function sfJson(args) {
  const result = spawnSync('sf', args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  if (result.status !== 0) {
    throw new Error(`sf ${args.join(' ')} failed\n${result.stdout}\n${result.stderr}`);
  }
  const start = result.stdout.indexOf('{');
  if (start === -1) {
    throw new Error(`sf ${args.join(' ')} did not return JSON\n${result.stdout}`);
  }
  return JSON.parse(result.stdout.slice(start));
}

function eventRouteName(index) {
  return `${EVENT_ROUTE_PREFIX}${String(index).padStart(2, '0')}`;
}

function escapeApexString(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function slug(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 80);
}

function sleep(ms) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, ms));
}
