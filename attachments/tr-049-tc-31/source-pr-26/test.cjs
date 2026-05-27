'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const runner = require('./backfill-manual-analytics-runs.cjs');

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'im-768-backfill-'));
}

function makeOrgIds(count) {
  return Array.from({ length: count }, (_, index) => `00D${String(index).padStart(15, 'A')}`.slice(0, 18));
}

function response(payload, status = 202) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => JSON.stringify(payload),
  };
}

test('extracts and dedupes org ids without exposing raw ids in progress planning metadata', () => {
  const orgIds = runner.extractUniqueOrgIdsFromText(`
    export const ids = ["00DAAAAAAAAAAAAAAA", "00DBBBBBBBBBBBBBBB", "00DAAAAAAAAAAAAAAA"];
  `);

  assert.deepEqual(orgIds, ['00DAAAAAAAAAAAAAAA', '00DBBBBBBBBBBBBBBB']);
  const [workItem] = runner.planWorkItems({
    periods: runner.generateMonthlyPeriods({ startDate: '2026-03-01', endDate: '2026-03-31' }),
    orgIds,
    orgBatchSize: 2,
  });
  const progress = runner.makeEmptyProgress();
  runner.writeProgress(path.join(tempDir(), 'progress.json'), {
    ...progress,
    records: [
      {
        id: workItem.id,
        period: workItem.period,
        orgBatch: { index: workItem.orgBatch.index, size: workItem.orgBatch.size, hash: workItem.orgBatch.hash },
      },
    ],
  });
  assert.equal(workItem.orgBatch.size, 2);
  assert.equal(typeof workItem.orgBatch.hash, 'string');
});

test('generates full monthly periods in newest-first and oldest-first order', () => {
  assert.deepEqual(
    runner.generateMonthlyPeriods({ startDate: '2026-01-15', endDate: '2026-03-02', order: 'newest-first' }),
    [
      { periodKey: '2026-03', periodStart: '2026-03-01', periodEnd: '2026-03-31' },
      { periodKey: '2026-02', periodStart: '2026-02-01', periodEnd: '2026-02-28' },
      { periodKey: '2026-01', periodStart: '2026-01-01', periodEnd: '2026-01-31' },
    ],
  );
  assert.deepEqual(
    runner.generateMonthlyPeriods({ startDate: '2026-01-15', endDate: '2026-03-02', order: 'oldest-first' }).map((p) => p.periodKey),
    ['2026-01', '2026-02', '2026-03'],
  );
});

test('rejects invalid dates and backwards ranges before API calls', () => {
  assert.throws(
    () => runner.generateMonthlyPeriods({ startDate: '2026-02-30', endDate: '2026-03-31' }),
    /startDate must be a valid calendar date/,
  );
  assert.throws(
    () => runner.generateMonthlyPeriods({ startDate: '2026-04-01', endDate: '2026-03-31' }),
    /startDate must be before or equal to endDate/,
  );
});

test('normalizes config without requiring API key for dry-run and rejects CLI secrets', () => {
  const args = runner.parseArgs([
    '--start-date', '2026-01-01',
    '--end-date', '2026-01-31',
    '--org-file', 'ids.js',
    '--dry-run',
  ]);
  const config = runner.normalizeConfig(args, {});
  assert.equal(config.dryRun, true);
  assert.equal(config.apiKey, undefined);
  assert.throws(
    () => runner.normalizeConfig({ ...args, 'api-key': 'secret' }, {}),
    /Do not pass API keys via --api-key/,
  );
});


test('accepts direct subscriber org ids as a JSON-style list of strings', () => {
  const args = runner.parseArgs([
    '--start-date', '2026-01-01',
    '--end-date', '2026-01-31',
    '--subscriber-org-ids', '["00DAAAAAAAAAAAAAAA", "00DBBBBBBBBBBBBBBB", "00DAAAAAAAAAAAAAAA"]',
    '--dry-run',
  ]);
  const config = runner.normalizeConfig(args, {});
  assert.equal(config.orgFile, undefined);
  assert.deepEqual(runner.resolveOrgIds(config), ['00DAAAAAAAAAAAAAAA', '00DBBBBBBBBBBBBBBB']);
});

test('accepts repeated direct subscriber org id flags and comma-separated values', () => {
  const args = runner.parseArgs([
    '--start-date', '2026-01-01',
    '--end-date', '2026-01-31',
    '--subscriber-org-id', '00DAAAAAAAAAAAAAAA',
    '--subscriber-org-id', '00DBBBBBBBBBBBBBBB,00DCCCCCCCCCCCCCCC',
    '--dry-run',
  ]);
  const config = runner.normalizeConfig(args, {});
  assert.deepEqual(runner.resolveOrgIds(config), [
    '00DAAAAAAAAAAAAAAA',
    '00DBBBBBBBBBBBBBBB',
    '00DCCCCCCCCCCCCCCC',
  ]);
});

test('requires exactly one org source', () => {
  const baseArgs = {
    'start-date': '2026-01-01',
    'end-date': '2026-01-31',
    'dry-run': 'true',
  };
  assert.throws(
    () => runner.normalizeConfig(baseArgs, {}),
    /Provide either --org-file or --subscriber-org-ids/,
  );
  assert.throws(
    () => runner.normalizeConfig({ ...baseArgs, 'org-file': 'ids.js', 'subscriber-org-ids': '["00DAAAAAAAAAAAAAAA"]' }, {}),
    /Use only one org source/,
  );
});

test('rejects invalid direct subscriber org ids before planning', () => {
  assert.throws(
    () => runner.parseSubscriberOrgIdsInput('["00DAAAAAAAAAAAAAAA", "not-an-org"]'),
    /Invalid Salesforce subscriber org ID\(s\): not-an-org/,
  );
});


test('builds manual-runs request with fixed endpoint, x-api-key header, monthly payload, and no CLI API key', () => {
  const [workItem] = runner.planWorkItems({
    periods: runner.generateMonthlyPeriods({ startDate: '2026-03-01', endDate: '2026-03-31' }),
    orgIds: ['00DAAAAAAAAAAAAAAA', '00DBBBBBBBBBBBBBBB'],
    orgBatchSize: 10,
  });
  const request = runner.buildManualRunRequest(workItem, { apiKey: 'sentinel-secret', reason: 'test reason' });
  assert.equal(request.url, runner.MANUAL_RUNS_ENDPOINT);
  assert.equal(request.headers['x-api-key'], 'sentinel-secret');
  assert.deepEqual(JSON.parse(request.body), {
    periodStart: '2026-03-01',
    periodEnd: '2026-03-31',
    subscriberOrgIds: ['00DAAAAAAAAAAAAAAA', '00DBBBBBBBBBBBBBBB'],
    reason: 'test reason',
  });
});

test('skips succeeded resume records and executes pending records only', async () => {
  const dir = tempDir();
  const config = {
    apiKey: 'sentinel-secret',
    reason: 'resume test',
    resumeFile: path.join(dir, 'progress.json'),
    pollIntervalMs: 1,
    executionTimeoutMs: 1000,
    failurePolicy: 'stop',
    delayBetweenRunsMs: 0,
  };
  const workItems = runner.planWorkItems({
    periods: runner.generateMonthlyPeriods({ startDate: '2026-01-01', endDate: '2026-02-28', order: 'oldest-first' }),
    orgIds: ['00DAAAAAAAAAAAAAAA'],
    orgBatchSize: 1,
  });
  const progress = {
    version: 1,
    records: [
      {
        id: workItems[0].id,
        status: 'succeeded',
        stepFunctionsStatus: 'SUCCEEDED',
      },
    ],
  };
  const started = [];
  await runner.executeWorkItems({
    workItems,
    progress,
    config,
    fetchFn: async (_url, options) => {
      started.push(JSON.parse(options.body).periodStart);
      return response({ executionArn: 'arn:aws:states:us-east-1:123456789012:execution:test:second' });
    },
    describeExecutionFnFactory: () => async () => ({ status: 'SUCCEEDED', stopDate: new Date('2026-01-01T00:00:00Z') }),
    sleepFn: async () => {},
  });
  assert.deepEqual(started, ['2026-02-01']);
});

test('does not start the next API call until DescribeExecution reaches terminal status', async () => {
  const dir = tempDir();
  const config = {
    apiKey: 'sentinel-secret',
    reason: 'sequential test',
    resumeFile: path.join(dir, 'progress.json'),
    pollIntervalMs: 1,
    executionTimeoutMs: 1000,
    failurePolicy: 'stop',
    delayBetweenRunsMs: 0,
  };
  const workItems = runner.planWorkItems({
    periods: runner.generateMonthlyPeriods({ startDate: '2026-01-01', endDate: '2026-02-28', order: 'oldest-first' }),
    orgIds: ['00DAAAAAAAAAAAAAAA'],
    orgBatchSize: 1,
  });
  const events = [];
  let requestIndex = 0;
  const describeCallsByArn = new Map();
  await runner.executeWorkItems({
    workItems,
    progress: runner.makeEmptyProgress(),
    config,
    fetchFn: async (_url, options) => {
      requestIndex += 1;
      events.push(`start-${requestIndex}-${JSON.parse(options.body).periodStart}`);
      return response({ executionArn: `arn:aws:states:us-east-1:123456789012:execution:test:${requestIndex}` });
    },
    describeExecutionFnFactory: (arn) => async () => {
      const count = (describeCallsByArn.get(arn) || 0) + 1;
      describeCallsByArn.set(arn, count);
      events.push(`poll-${arn.split(':').pop()}-${count}`);
      return { status: count === 1 ? 'RUNNING' : 'SUCCEEDED', stopDate: new Date('2026-01-01T00:00:00Z') };
    },
    sleepFn: async () => {},
  });
  assert.deepEqual(events, [
    'start-1-2026-01-01',
    'poll-1-1',
    'poll-1-2',
    'start-2-2026-02-01',
    'poll-2-1',
    'poll-2-2',
  ]);
});

test('records terminal failure and stops by default', async () => {
  const dir = tempDir();
  const config = {
    apiKey: 'sentinel-secret',
    reason: 'failure test',
    resumeFile: path.join(dir, 'progress.json'),
    pollIntervalMs: 1,
    executionTimeoutMs: 1000,
    failurePolicy: 'stop',
    delayBetweenRunsMs: 0,
  };
  const [workItem] = runner.planWorkItems({
    periods: runner.generateMonthlyPeriods({ startDate: '2026-01-01', endDate: '2026-01-31' }),
    orgIds: ['00DAAAAAAAAAAAAAAA'],
    orgBatchSize: 1,
  });
  await assert.rejects(
    () => runner.executeWorkItems({
      workItems: [workItem],
      progress: runner.makeEmptyProgress(),
      config,
      fetchFn: async () => response({ executionArn: 'arn:aws:states:us-east-1:123456789012:execution:test:failed' }),
      describeExecutionFnFactory: () => async () => ({ status: 'FAILED', error: 'TestError', cause: 'fixture' }),
      sleepFn: async () => {},
    }),
    /ended with FAILED/,
  );
  const saved = JSON.parse(fs.readFileSync(config.resumeFile, 'utf8'));
  assert.equal(saved.records[0].status, 'failed');
  assert.equal(JSON.stringify(saved).includes('sentinel-secret'), false);
});


test('preflights Step Functions dependency before non-dry-run API calls', () => {
  assert.throws(
    () => runner.assertRuntimeDependencies({ requireResolveFn: () => { throw new Error('missing'); } }),
    /Missing dependency @aws-sdk\/client-sfn/,
  );
});

test('resumes polling an existing execution ARN instead of starting a duplicate API call', async () => {
  const dir = tempDir();
  const config = {
    apiKey: 'sentinel-secret',
    reason: 'resume existing execution test',
    resumeFile: path.join(dir, 'progress.json'),
    pollIntervalMs: 1,
    executionTimeoutMs: 1000,
    failurePolicy: 'stop',
    delayBetweenRunsMs: 0,
  };
  const [workItem] = runner.planWorkItems({
    periods: runner.generateMonthlyPeriods({ startDate: '2025-11-01', endDate: '2025-11-30' }),
    orgIds: ['00D5e000005BCc7EAG'],
    orgBatchSize: 1,
  });
  const executionArn = 'arn:aws:states:us-east-1:123456789012:execution:test:already-started';
  const progress = {
    version: 1,
    records: [
      {
        id: workItem.id,
        period: workItem.period,
        orgBatch: { index: 1, size: 1, hash: workItem.orgBatch.hash },
        executionArn,
        status: 'failed',
        startedAt: '2026-05-27T14:38:40.337Z',
        failure: { message: 'local dependency missing' },
      },
    ],
  };
  let apiCalls = 0;
  const results = await runner.executeWorkItems({
    workItems: [workItem],
    progress,
    config,
    fetchFn: async () => {
      apiCalls += 1;
      return response({ executionArn: 'should-not-be-used' });
    },
    describeExecutionFnFactory: (arn) => async () => ({ status: 'SUCCEEDED', stopDate: new Date('2026-01-01T00:00:00Z'), arn }),
    sleepFn: async () => {},
  });
  assert.equal(apiCalls, 0);
  assert.equal(results[0].executionArn, executionArn);
  assert.equal(results[0].status, 'succeeded');
});


test('infers Step Functions region from execution arn', () => {
  assert.equal(
    runner.inferRegionFromExecutionArn('arn:aws:states:us-east-2:123456789012:execution:machine:name'),
    'us-east-2',
  );
});
