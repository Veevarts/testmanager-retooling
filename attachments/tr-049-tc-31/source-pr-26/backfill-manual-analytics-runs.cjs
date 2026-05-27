#!/usr/bin/env node
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const MANUAL_RUNS_ENDPOINT =
  'https://dcaxoa4js4.execute-api.us-east-1.amazonaws.com/prod/analytics/manual-runs';
const DEFAULT_API_KEY_ENV = 'MANUAL_EXTRACTION_API_KEY';
const DEFAULT_ORDER = 'newest-first';
const DEFAULT_ORG_BATCH_SIZE = 10;
const DEFAULT_DELAY_BETWEEN_RUNS_MS = 5_000;
const DEFAULT_POLL_INTERVAL_MS = 30_000;
const DEFAULT_EXECUTION_TIMEOUT_MS = 6 * 60 * 60 * 1000;
const DEFAULT_FAILURE_POLICY = 'stop';
const DEFAULT_RESUME_FILE = 'backfill-manual-analytics-runs.progress.json';
const SALESFORCE_ORG_ID_PATTERN = /\b00D[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?\b/g;
const TERMINAL_EXECUTION_STATUSES = new Set(['SUCCEEDED', 'FAILED', 'TIMED_OUT', 'ABORTED']);

function assignArg(args, key, value) {
  if (Object.prototype.hasOwnProperty.call(args, key)) {
    args[key] = Array.isArray(args[key]) ? [...args[key], value] : [args[key], value];
    return;
  }
  args[key] = value;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const raw = argv[i];
    if (raw === '--') continue;
    if (!raw.startsWith('--')) continue;

    const withoutPrefix = raw.slice(2);
    const equalsIndex = withoutPrefix.indexOf('=');
    if (equalsIndex >= 0) {
      const key = withoutPrefix.slice(0, equalsIndex);
      assignArg(args, key, withoutPrefix.slice(equalsIndex + 1));
      continue;
    }

    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      assignArg(args, withoutPrefix, 'true');
      continue;
    }

    assignArg(args, withoutPrefix, next);
    i += 1;
  }
  return args;
}

function asBoolean(value) {
  return value === true || value === 'true' || value === '1' || value === 'yes';
}

function parseIntegerArg(value, name, { min }) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min) {
    throw new Error(`${name} must be an integer greater than or equal to ${min}.`);
  }
  return parsed;
}

function normalizeConfig(args, env = process.env) {
  for (const forbidden of ['api-key', 'x-api-key', 'manual-extraction-api-key']) {
    if (Object.prototype.hasOwnProperty.call(args, forbidden)) {
      throw new Error(`Do not pass API keys via --${forbidden}; use ${DEFAULT_API_KEY_ENV}.`);
    }
  }

  const startDate = args['start-date'];
  const endDate = args['end-date'];
  const orgFile = args['org-file'];
  const subscriberOrgIdsInput = args['subscriber-org-ids'] || args['subscriber-org-id'];
  if (!startDate) throw new Error('--start-date is required.');
  if (!endDate) throw new Error('--end-date is required.');
  if (!orgFile && !subscriberOrgIdsInput) {
    throw new Error('Provide either --org-file or --subscriber-org-ids.');
  }
  if (orgFile && subscriberOrgIdsInput) {
    throw new Error('Use only one org source: --org-file or --subscriber-org-ids.');
  }

  const order = args.order || DEFAULT_ORDER;
  if (!['newest-first', 'oldest-first'].includes(order)) {
    throw new Error('--order must be newest-first or oldest-first.');
  }

  const failurePolicy = args['failure-policy'] || DEFAULT_FAILURE_POLICY;
  if (!['stop', 'continue'].includes(failurePolicy)) {
    throw new Error('--failure-policy must be stop or continue.');
  }

  const dryRun = asBoolean(args['dry-run']);
  const apiKeyEnv = args['api-key-env'] || DEFAULT_API_KEY_ENV;
  const apiKey = env[apiKeyEnv]?.trim();
  if (!dryRun && !apiKey) {
    throw new Error(`${apiKeyEnv} is required before running without --dry-run.`);
  }

  return {
    startDate,
    endDate,
    order,
    orgFile,
    subscriberOrgIdsInput,
    orgBatchSize: parseIntegerArg(args['org-batch-size'] || DEFAULT_ORG_BATCH_SIZE, '--org-batch-size', { min: 1 }),
    delayBetweenRunsMs: parseIntegerArg(args['delay-between-runs'] || args['delay-between-runs-ms'] || DEFAULT_DELAY_BETWEEN_RUNS_MS, '--delay-between-runs', { min: 0 }),
    dryRun,
    resumeFile: args['resume-file'] || DEFAULT_RESUME_FILE,
    apiKeyEnv,
    apiKey,
    awsRegion: args['aws-region'],
    awsProfile: args['aws-profile'],
    pollIntervalMs: parseIntegerArg(args['poll-interval-ms'] || DEFAULT_POLL_INTERVAL_MS, '--poll-interval-ms', { min: 1 }),
    executionTimeoutMs: parseIntegerArg(args['execution-timeout-ms'] || DEFAULT_EXECUTION_TIMEOUT_MS, '--execution-timeout-ms', { min: 1 }),
    failurePolicy,
    reason: args.reason || 'IM-768 historical analytics backfill',
  };
}

function formatDate(date) {
  return date.toISOString().slice(0, 10);
}

function parseIsoDateOnly(value, name) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${name} must be an ISO date in YYYY-MM-DD format.`);
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || formatDate(date) !== value) {
    throw new Error(`${name} must be a valid calendar date.`);
  }
  return date;
}

function monthPeriodFor(year, monthIndex) {
  const first = new Date(Date.UTC(year, monthIndex, 1));
  const last = new Date(Date.UTC(year, monthIndex + 1, 0));
  const month = String(monthIndex + 1).padStart(2, '0');
  return {
    periodKey: `${year}-${month}`,
    periodStart: formatDate(first),
    periodEnd: formatDate(last),
  };
}

function generateMonthlyPeriods({ startDate, endDate, order = DEFAULT_ORDER }) {
  const start = parseIsoDateOnly(startDate, 'startDate');
  const end = parseIsoDateOnly(endDate, 'endDate');
  if (start.getTime() > end.getTime()) {
    throw new Error('startDate must be before or equal to endDate.');
  }
  if (!['newest-first', 'oldest-first'].includes(order)) {
    throw new Error('order must be newest-first or oldest-first.');
  }

  const periods = [];
  let cursor = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));
  const endCursor = new Date(Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), 1));
  while (cursor.getTime() <= endCursor.getTime()) {
    periods.push(monthPeriodFor(cursor.getUTCFullYear(), cursor.getUTCMonth()));
    cursor = new Date(Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 1));
  }

  return order === 'newest-first' ? periods.reverse() : periods;
}

function dedupeOrgIds(orgIds) {
  const seen = new Set();
  const output = [];
  for (const orgId of orgIds) {
    if (!seen.has(orgId)) {
      seen.add(orgId);
      output.push(orgId);
    }
  }
  return output;
}

function extractUniqueOrgIdsFromText(text) {
  return dedupeOrgIds([...text.matchAll(SALESFORCE_ORG_ID_PATTERN)].map((match) => match[0]));
}

function normalizeStringListInput(value) {
  if (Array.isArray(value)) {
    return value.flatMap((entry) => normalizeStringListInput(entry));
  }
  const raw = String(value || '').trim();
  if (!raw) return [];

  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      return parsed.map((entry) => String(entry));
    }
  } catch {
    // Fall back to delimiter parsing below.
  }

  return raw
    .split(/[\s,]+/)
    .map((entry) => entry.trim().replace(/^['"]|['"]$/g, ''))
    .filter(Boolean);
}

function isSalesforceOrgId(value) {
  return /^00D[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?$/.test(value);
}

function parseSubscriberOrgIdsInput(value) {
  const candidates = normalizeStringListInput(value);
  const invalid = candidates.filter((candidate) => !isSalesforceOrgId(candidate));
  if (invalid.length > 0) {
    throw new Error(`Invalid Salesforce subscriber org ID(s): ${invalid.join(', ')}.`);
  }
  return dedupeOrgIds(candidates);
}

function loadOrgIdsFromFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  return extractUniqueOrgIdsFromText(content);
}

function resolveOrgIds(config) {
  if (config.orgFile) {
    const orgIds = loadOrgIdsFromFile(config.orgFile);
    if (orgIds.length === 0) {
      throw new Error(`No Salesforce org IDs were found in ${config.orgFile}.`);
    }
    return orgIds;
  }

  const orgIds = parseSubscriberOrgIdsInput(config.subscriberOrgIdsInput);
  if (orgIds.length === 0) {
    throw new Error('No Salesforce org IDs were provided in --subscriber-org-ids.');
  }
  return orgIds;
}

function hashOrgIds(orgIds) {
  return crypto.createHash('sha256').update(orgIds.join('\n')).digest('hex').slice(0, 12);
}

function chunkArray(values, chunkSize) {
  const chunks = [];
  for (let i = 0; i < values.length; i += chunkSize) {
    chunks.push(values.slice(i, i + chunkSize));
  }
  return chunks;
}

function planWorkItems({ periods, orgIds, orgBatchSize }) {
  const orgBatches = chunkArray(orgIds, orgBatchSize).map((orgIdsForBatch, index) => ({
    index: index + 1,
    size: orgIdsForBatch.length,
    hash: hashOrgIds(orgIdsForBatch),
    subscriberOrgIds: orgIdsForBatch,
  }));

  return periods.flatMap((period) =>
    orgBatches.map((orgBatch) => ({
      id: `${period.periodKey}::batch-${String(orgBatch.index).padStart(4, '0')}::${orgBatch.hash}`,
      period,
      orgBatch,
    })),
  );
}

function makeEmptyProgress() {
  return { version: 1, records: [] };
}

function loadProgress(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return makeEmptyProgress();
  const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (!Array.isArray(parsed.records)) {
    throw new Error(`Progress file ${filePath} must contain a records array.`);
  }
  return { version: parsed.version || 1, records: parsed.records };
}

function progressMap(progress) {
  return new Map(progress.records.map((record) => [record.id, record]));
}

function writeProgress(filePath, progress) {
  const safeProgress = {
    version: progress.version || 1,
    updatedAt: new Date().toISOString(),
    records: progress.records,
  };
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(safeProgress, null, 2)}\n`);
}

function isSucceededRecord(record) {
  return record?.status === 'succeeded' || record?.stepFunctionsStatus === 'SUCCEEDED';
}

function upsertProgressRecord(progress, record) {
  const recordsById = progressMap(progress);
  recordsById.set(record.id, record);
  progress.records = [...recordsById.values()].sort((a, b) => a.id.localeCompare(b.id));
  return record;
}

function progressRecordFromWorkItem(workItem, patch = {}) {
  return {
    id: workItem.id,
    period: workItem.period,
    orgBatch: {
      index: workItem.orgBatch.index,
      size: workItem.orgBatch.size,
      hash: workItem.orgBatch.hash,
    },
    ...patch,
  };
}

function buildManualRunRequest(workItem, { apiKey, reason }) {
  if (!apiKey) throw new Error(`${DEFAULT_API_KEY_ENV} is required before calling the manual-runs endpoint.`);
  return {
    url: MANUAL_RUNS_ENDPOINT,
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
    },
    body: JSON.stringify({
      periodStart: workItem.period.periodStart,
      periodEnd: workItem.period.periodEnd,
      subscriberOrgIds: workItem.orgBatch.subscriberOrgIds,
      reason,
    }),
  };
}

async function startManualRun(workItem, { apiKey, reason, fetchFn = globalThis.fetch }) {
  if (typeof fetchFn !== 'function') {
    throw new Error('fetch is not available in this Node.js runtime.');
  }
  const request = buildManualRunRequest(workItem, { apiKey, reason });
  const response = await fetchFn(request.url, {
    method: request.method,
    headers: request.headers,
    body: request.body,
  });

  let payload;
  const responseText = await response.text();
  try {
    payload = responseText ? JSON.parse(responseText) : {};
  } catch {
    payload = { raw: responseText };
  }

  if (!response.ok) {
    throw new Error(`manual-runs request failed with HTTP ${response.status}: ${JSON.stringify(payload).slice(0, 500)}`);
  }
  if (!payload.executionArn) {
    throw new Error('manual-runs response did not include executionArn.');
  }
  return payload;
}

function inferRegionFromExecutionArn(executionArn) {
  const parts = executionArn.split(':');
  return parts[0] === 'arn' && parts[2] === 'states' ? parts[3] : undefined;
}

function assertRuntimeDependencies({ requireResolveFn = require.resolve } = {}) {
  try {
    requireResolveFn('@aws-sdk/client-sfn');
  } catch (error) {
    throw new Error('Missing dependency @aws-sdk/client-sfn. Run `pnpm --dir veevart-analytics install --frozen-lockfile` before running without --dry-run.');
  }
}

function createSfnClient({ awsRegion, awsProfile, executionArn }) {
  if (awsProfile) process.env.AWS_PROFILE = awsProfile;
  const region = awsRegion || inferRegionFromExecutionArn(executionArn) || process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1';
  const { SFNClient } = require('@aws-sdk/client-sfn');
  return new SFNClient({ region });
}

function createDescribeExecutionFn({ awsRegion, awsProfile, executionArn }) {
  const client = createSfnClient({ awsRegion, awsProfile, executionArn });
  const describeExecution = async (arn) => {
    const { DescribeExecutionCommand } = require('@aws-sdk/client-sfn');
    const response = await client.send(new DescribeExecutionCommand({ executionArn: arn }));
    return response;
  };
  describeExecution.destroy = () => client.destroy();
  return describeExecution;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeExecutionStatus(status) {
  if (status === 'SUCCEEDED') return 'succeeded';
  if (status === 'FAILED') return 'failed';
  if (status === 'TIMED_OUT') return 'timed_out';
  if (status === 'ABORTED') return 'aborted';
  return 'running';
}

async function waitForExecution({ executionArn, describeExecutionFn, sleepFn = sleep, pollIntervalMs, executionTimeoutMs, nowFn = () => Date.now() }) {
  const startedAtMs = nowFn();
  let pollCount = 0;
  while (true) {
    const response = await describeExecutionFn(executionArn);
    pollCount += 1;
    const status = response.status;
    if (TERMINAL_EXECUTION_STATUSES.has(status)) {
      return { ...response, status, pollCount };
    }

    const elapsedMs = nowFn() - startedAtMs;
    if (elapsedMs >= executionTimeoutMs) {
      throw new Error(`Execution ${executionArn} did not reach a terminal status within ${executionTimeoutMs}ms.`);
    }

    await sleepFn(Math.min(pollIntervalMs, executionTimeoutMs - elapsedMs));
  }
}

async function executeWorkItems({ workItems, progress, config, fetchFn, describeExecutionFnFactory, sleepFn = sleep }) {
  const recordsById = progressMap(progress);
  const pending = workItems.filter((item) => !isSucceededRecord(recordsById.get(item.id)));
  const results = [];

  for (let index = 0; index < pending.length; index += 1) {
    const workItem = pending[index];
    const existingRecord = recordsById.get(workItem.id);
    const reusableExecutionArn = existingRecord?.executionArn && !TERMINAL_EXECUTION_STATUSES.has(existingRecord.stepFunctionsStatus)
      ? existingRecord.executionArn
      : undefined;
    const startedAt = reusableExecutionArn && existingRecord?.startedAt ? existingRecord.startedAt : new Date().toISOString();
    const executionArn = reusableExecutionArn || (await startManualRun(workItem, { apiKey: config.apiKey, reason: config.reason, fetchFn })).executionArn;
    const startedRecord = progressRecordFromWorkItem(workItem, {
      executionArn,
      status: reusableExecutionArn ? 'running' : 'started',
      startedAt,
      ...(reusableExecutionArn ? { resumedAt: new Date().toISOString() } : {}),
    });
    upsertProgressRecord(progress, startedRecord);
    recordsById.set(workItem.id, startedRecord);
    writeProgress(config.resumeFile, progress);

    let terminal;
    let describeExecutionFn;
    try {
      describeExecutionFn = describeExecutionFnFactory
        ? describeExecutionFnFactory(executionArn)
        : createDescribeExecutionFn({ awsRegion: config.awsRegion, awsProfile: config.awsProfile, executionArn });
      terminal = await waitForExecution({
        executionArn,
        describeExecutionFn,
        sleepFn,
        pollIntervalMs: config.pollIntervalMs,
        executionTimeoutMs: config.executionTimeoutMs,
      });
    } catch (error) {
      const failedRecord = progressRecordFromWorkItem(workItem, {
        ...startedRecord,
        status: 'failed',
        failure: { message: error instanceof Error ? error.message : String(error) },
        stoppedAt: new Date().toISOString(),
      });
      upsertProgressRecord(progress, failedRecord);
      writeProgress(config.resumeFile, progress);
      throw error;
    } finally {
      if (typeof describeExecutionFn?.destroy === 'function') {
        describeExecutionFn.destroy();
      }
    }

    const terminalStatus = normalizeExecutionStatus(terminal.status);
    const terminalRecord = progressRecordFromWorkItem(workItem, {
      ...startedRecord,
      status: terminalStatus,
      stepFunctionsStatus: terminal.status,
      pollCount: terminal.pollCount,
      stoppedAt: terminal.stopDate instanceof Date ? terminal.stopDate.toISOString() : new Date().toISOString(),
      ...(terminal.error || terminal.cause
        ? { failure: { error: terminal.error, cause: terminal.cause } }
        : {}),
    });
    upsertProgressRecord(progress, terminalRecord);
    writeProgress(config.resumeFile, progress);
    results.push(terminalRecord);

    if (terminal.status !== 'SUCCEEDED' && config.failurePolicy === 'stop') {
      throw new Error(`Execution ${executionArn} ended with ${terminal.status}.`);
    }

    if (index < pending.length - 1 && config.delayBetweenRunsMs > 0) {
      await sleepFn(config.delayBetweenRunsMs);
    }
  }

  return results;
}

function buildPlan(config) {
  const orgIds = resolveOrgIds(config);
  const periods = generateMonthlyPeriods({
    startDate: config.startDate,
    endDate: config.endDate,
    order: config.order,
  });
  const workItems = planWorkItems({ periods, orgIds, orgBatchSize: config.orgBatchSize });
  return { orgIds, periods, workItems };
}

function printDryRunSummary({ orgIds, periods, workItems, config, output = console.log }) {
  output('Dry run only; no API or AWS calls were made.');
  output(`Endpoint: ${MANUAL_RUNS_ENDPOINT}`);
  output(`Unique org IDs: ${orgIds.length}`);
  output(`Periods: ${periods.length} (${periods[0].periodKey} -> ${periods[periods.length - 1].periodKey}, ${config.order})`);
  output(`Org batch size: ${config.orgBatchSize}`);
  output(`Planned manual-runs calls: ${workItems.length}`);
  output(`Resume file: ${config.resumeFile}`);
}

async function main(argv = process.argv.slice(2), env = process.env) {
  const config = normalizeConfig(parseArgs(argv), env);
  if (!config.dryRun) {
    assertRuntimeDependencies();
  }
  const plan = buildPlan(config);
  if (config.dryRun) {
    printDryRunSummary({ ...plan, config });
    return;
  }

  const progress = loadProgress(config.resumeFile);
  const existing = progressMap(progress);
  const pendingCount = plan.workItems.filter((item) => !isSucceededRecord(existing.get(item.id))).length;
  console.log(`Starting ${pendingCount} pending manual-runs work items out of ${plan.workItems.length} planned.`);
  const results = await executeWorkItems({ workItems: plan.workItems, progress, config });
  console.log(`Completed ${results.length} work items. Progress saved to ${config.resumeFile}.`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}

module.exports = {
  MANUAL_RUNS_ENDPOINT,
  DEFAULT_API_KEY_ENV,
  parseArgs,
  normalizeConfig,
  generateMonthlyPeriods,
  extractUniqueOrgIdsFromText,
  parseSubscriberOrgIdsInput,
  resolveOrgIds,
  hashOrgIds,
  planWorkItems,
  buildManualRunRequest,
  inferRegionFromExecutionArn,
  assertRuntimeDependencies,
  waitForExecution,
  executeWorkItems,
  makeEmptyProgress,
  loadProgress,
  writeProgress,
  isSucceededRecord,
  buildPlan,
};
