/**
 * TR-219 / TC-191 (IM-1202) - QA harness, NOT part of the PR.
 *
 * Real code path for the terminal report: MigrationAppBackendModule (config
 * factory from env) -> MigrationAppBackendAdapter (real fetch) ->
 * UpdateMigrationObjectFilesUseCase / UpdateMigrationStatusUseCase ->
 * RunMigrationUseCase.execute. Only the data plane (runPipelineFlow:
 * extract/transform/CSV/upload) is stubbed. The backend is a real HTTP server on
 * 127.0.0.1 that answers like the VPC endpoint did (403 ForbiddenException) or
 * like API Gateway (200), per path.
 */
import { MigrationAppBackendModule } from '@data-migration/infrastructure/destination/migration-app-backend/migration-app-backend.module';
import { MIGRATION_BACKEND_PORT } from '@data-migration/application/ports/migration-backend.port';
import { UpdateMigrationObjectFilesUseCase } from '@data-migration/application/use-cases/update-migration-object-files.use-case';
import { UpdateMigrationStatusUseCase } from '@data-migration/application/use-cases/update-migration-status.use-case';
import { RunMigrationUseCase } from '@data-migration/application/use-cases/run-migration.use-case';
import { MigrationObject } from '@data-migration/domain/enums/migration-object.enum';
import { ConfigModule } from '@nestjs/config';
import { Logger } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as fs from 'fs';
import * as http from 'http';

type Mode = 'deny' | 'ok' | 'hang' | '503';
interface Hit { t: number; method: string; kind: 'files' | 'status'; object?: string; body: any; apiKeyPresent: boolean }

const OUT = process.env.QA_OUT || '/tmp/qa-tc191-out';
const API_KEY = 'QA-FAKE-ETL-KEY-7f3a91';
const RUN = 'qa-run-0001';
const CLIENT = 'qa-client-0001';

let server: http.Server;
let base = '';
let hits: Hit[] = [];
let route: (kind: 'files' | 'status', object?: string) => Mode = () => 'ok';
const logs: Array<{ level: string; msg: string }> = [];

const record = (level: string) => (...args: any[]) => {
  logs.push({ level, msg: args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ') });
};

beforeAll(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  server = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => {
      const m = req.url!.match(/\/objects\/([^/]+)\/files$/);
      const kind = m ? 'files' : 'status';
      const object = m ? decodeURIComponent(m[1]) : undefined;
      hits.push({ t: Date.now(), method: req.method!, kind, object, body: raw ? JSON.parse(raw) : null, apiKeyPresent: req.headers['x-api-key'] === API_KEY });
      const mode = route(kind, object);
      if (mode === 'hang') return; // never answers: the per-attempt AbortSignal must cut it
      if (mode === 'deny') {
        res.writeHead(403, { 'content-type': 'application/json', 'x-amzn-errortype': 'ForbiddenException' });
        return res.end('{"message":"Forbidden"}');
      }
      if (mode === '503') { res.writeHead(503); return res.end('unavailable'); }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end('{"ok":true}');
    });
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', () => r()));
  base = `http://127.0.0.1:${(server.address() as any).port}`;
});

afterAll(async () => {
  fs.writeFileSync(`${OUT}/logs.json`, JSON.stringify(logs, null, 1));
  server.closeAllConnections?.();
  await new Promise((r) => server.close(() => r(null)));
});

const build = async (env: Record<string, string>) => {
  for (const k of Object.keys(process.env)) if (k.startsWith('MIGRATION_APP_BACKEND_')) delete process.env[k];
  Object.assign(process.env, { MIGRATION_APP_BACKEND_URL: base, MIGRATION_APP_BACKEND_ETL_API_KEY: API_KEY, ...env });
  const mod = await Test.createTestingModule({
    imports: [ConfigModule.forRoot({ isGlobal: true, ignoreEnvFile: true }), MigrationAppBackendModule],
    providers: [UpdateMigrationObjectFilesUseCase, UpdateMigrationStatusUseCase],
  }).compile();
  const port = mod.get(MIGRATION_BACKEND_PORT);
  const useCase = new RunMigrationUseCase(
    { resolveMany: (objs: string[]) => objs.map((o) => ({ objectName: o })) } as any,
    {} as any, {} as any, {} as any, {} as any,
    mod.get(UpdateMigrationObjectFilesUseCase),
    mod.get(UpdateMigrationStatusUseCase),
    { getAdapter: () => ({}) } as any,
  );
  return { port, useCase, config: (port as any).config };
};

const file = (obj: MigrationObject, part: number) => ({
  objectName: `${obj.toLowerCase()}_part${part}`,
  sourceObjectName: obj,
  fileName: `${CLIENT}/migration/${RUN}/objects/${obj.toLowerCase()}_part${part}.csv`,
  etag: `etag-${obj}-${part}`,
  size: 100 * part,
  contentType: 'text/csv',
});

const run = async (useCase: RunMigrationUseCase, objects: MigrationObject[], files: any[]) => {
  jest.spyOn(useCase as any, 'runPipelineFlow').mockResolvedValue(files);
  return useCase.execute(CLIENT, RUN, objects, undefined, `${CLIENT}/migration/${RUN}`, 'db.local', 1433, 'qa_db', objects.map((o) => o.toUpperCase().replace(/-/g, '_')));
};

const gaps = (hs: Hit[]) => hs.slice(1).map((h, i) => h.t - hs[i].t);
const dump = (name: string, data: unknown) => fs.writeFileSync(`${OUT}/${name}.json`, JSON.stringify(data, null, 1));

beforeEach(() => {
  hits = [];
  logs.length = 0;
  jest.spyOn(Logger.prototype, 'log').mockImplementation(record('log'));
  jest.spyOn(Logger.prototype, 'warn').mockImplementation(record('warn'));
  jest.spyOn(Logger.prototype, 'error').mockImplementation(record('error'));
});
afterEach(() => jest.restoreAllMocks());

describe('TC-191 harness (real adapter + real HTTP)', () => {
  it('H1 AC4: persistent 403 on both callbacks -> retried with growing backoff, then one ERROR with run id and HTTP status', async () => {
    route = () => 'deny';
    const { useCase, config } = await build({});
    const t0 = Date.now();
    const result = await run(useCase, [MigrationObject.OPPORTUNITY_MEMBERSHIP], [file(MigrationObject.OPPORTUNITY_MEMBERSHIP, 1), file(MigrationObject.OPPORTUNITY_MEMBERSHIP, 2)]);
    const elapsed = Date.now() - t0;
    const put = hits.filter((h) => h.kind === 'files');
    const patch = hits.filter((h) => h.kind === 'status');
    const errors = logs.filter((l) => l.level === 'error');
    const undelivered = errors.filter((l) => l.msg.includes('migration.run.terminal.callback.undelivered'));
    const retries = logs.filter((l) => l.level === 'warn' && /callback\.retry/.test(l.msg));
    dump('H1', { config: { ...config, apiKey: '<omitted>', baseUrl: '<local>' }, elapsed, putCount: put.length, putGapsMs: gaps(put), patchCount: patch.length, patchGapsMs: gaps(patch), patchBody: patch[0]?.body, retryWarnCount: retries.length, undelivered: undelivered.map((u) => JSON.parse(u.msg)), result: { statusUpdateSuccess: result.statusUpdateSuccess, terminalCallbackFailure: result.terminalCallbackFailure } });
    expect(config.maxAttempts).toBe(4);
    expect(put).toHaveLength(4);
    expect(patch).toHaveLength(4);
    const g = gaps(put);
    expect(g[0]).toBeGreaterThanOrEqual(450);
    expect(g[1]).toBeGreaterThanOrEqual(950);
    expect(g[2]).toBeGreaterThanOrEqual(1950);
    expect(undelivered).toHaveLength(1);
    const payload = JSON.parse(undelivered[0].msg);
    expect(payload.migrationRunId).toBe(RUN);
    expect(payload.statusHttpStatus).toBe(403);
    expect(payload.statusAttempts).toBe(4);
    expect(result.statusUpdateSuccess).toBe(false);
  }, 60000);

  it('H2 edge: no inventory lands (PUT 403, PATCH 200) -> the run is reported FAILED, not COMPLETED', async () => {
    route = (kind) => (kind === 'files' ? 'deny' : 'ok');
    const { useCase } = await build({ MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '20', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '40' });
    const result = await run(useCase, [MigrationObject.OPPORTUNITY_MEMBERSHIP], [file(MigrationObject.OPPORTUNITY_MEMBERSHIP, 1)]);
    const patch = hits.filter((h) => h.kind === 'status');
    dump('H2', { patchBodies: patch.map((p) => p.body), statusUpdateSuccess: result.statusUpdateSuccess, errors: logs.filter((l) => l.level === 'error').map((l) => l.msg.slice(0, 300)) });
    expect(patch).toHaveLength(1);
    expect(patch[0].body.status).toBe('FAILED');
    expect(result.statusUpdateSuccess).toBe(false);
  }, 30000);

  it('H3 edge: partial inventory -> landed object keeps its files, run reports CSV_DONE with 1 completed / 1 failed', async () => {
    route = (kind, object) => (kind === 'files' && object === 'CONTACT' ? 'deny' : 'ok');
    const { useCase } = await build({ MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '20', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '40' });
    const result = await run(useCase, [MigrationObject.OPPORTUNITY_MEMBERSHIP, MigrationObject.CONTACT], [file(MigrationObject.OPPORTUNITY_MEMBERSHIP, 1), file(MigrationObject.CONTACT, 1)]);
    const put = hits.filter((h) => h.kind === 'files');
    const patch = hits.filter((h) => h.kind === 'status');
    dump('H3', { putPerObject: put.reduce((a: any, h) => ((a[h.object!] = (a[h.object!] || 0) + 1), a), {}), patchBodies: patch.map((p) => p.body), statusUpdateSuccess: result.statusUpdateSuccess, terminalCallbackFailure: result.terminalCallbackFailure });
    expect(patch).toHaveLength(1);
    expect(patch[0].body.status).not.toBe('FAILED');
    expect(patch[0].body.summary).toEqual({ totalObjects: 2, completed: 1, failed: 1 });
    expect(put.filter((h) => h.object === 'OPPORTUNITY_MEMBERSHIP')).toHaveLength(1);
  }, 30000);

  it('H4 edge: 503 on every files callback -> later objects get one attempt, but the status callback is never suppressed', async () => {
    let statusCalls = 0;
    route = (kind) => (kind === 'files' ? '503' : (statusCalls++ < 2 ? '503' : 'ok'));
    const { useCase } = await build({ MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '20', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '40' });
    const objs = [MigrationObject.OPPORTUNITY_MEMBERSHIP, MigrationObject.CONTACT, MigrationObject.CAMPAIGN];
    await run(useCase, objs, objs.map((o) => file(o, 1)));
    const put = hits.filter((h) => h.kind === 'files');
    const patch = hits.filter((h) => h.kind === 'status');
    const perObject = put.reduce((a: any, h) => ((a[h.object!] = (a[h.object!] || 0) + 1), a), {});
    dump('H4', { perObject, patchAttempts: patch.length, patchStatuses: patch.map((p) => p.body.status) });
    expect(perObject.OPPORTUNITY_MEMBERSHIP).toBe(4);
    expect(perObject.CONTACT).toBe(1);
    expect(perObject.CAMPAIGN).toBe(1);
    expect(patch).toHaveLength(3); // 503, 503, 200: retried, not suppressed
  }, 30000);

  it('H5 AC4/timeout: a hung backend is cut by the per-attempt deadline and still retried', async () => {
    route = () => 'hang';
    const { port } = await build({ MIGRATION_APP_BACKEND_TIMEOUT_MS: '300', MIGRATION_APP_BACKEND_MAX_ATTEMPTS: '3', MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '20', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '40' });
    const t0 = Date.now();
    const r = await (port as any).updateStatus({ clientId: CLIENT, migrationRunId: RUN, status: 'CSV_DONE' });
    const elapsed = Date.now() - t0;
    dump('H5', { attemptsSeenByServer: hits.length, result: r, elapsed });
    expect(hits).toHaveLength(3);
    expect(r.success).toBe(false);
    expect(elapsed).toBeLessThan(3000);
  }, 30000);

  it('H6 security: no log line carries the API key or the id-bearing URL path; the host is logged', async () => {
    route = () => 'deny';
    const { useCase } = await build({ MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '20', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '40' });
    await run(useCase, [MigrationObject.OPPORTUNITY_MEMBERSHIP], [file(MigrationObject.OPPORTUNITY_MEMBERSHIP, 1)]);
    const all = logs.map((l) => l.msg).join('\n');
    const host = base.replace('http://', '');
    dump('H6', { lines: logs.length, keyLeaks: all.split(API_KEY).length - 1, pathLeaks: (all.match(/\/api\/etl\/clients\//g) || []).length, hostMentions: all.split(host).length - 1, apiKeySentOnEveryRequest: hits.every((h) => h.apiKeyPresent) });
    expect(all).not.toContain(API_KEY);
    expect(all).not.toMatch(/\/api\/etl\/clients\//);
    expect(all).toContain(host);
    expect(hits.every((h) => h.apiKeyPresent)).toBe(true);
  }, 30000);

  it('H7 security/config: malformed values are rejected with a WARN and the defaults apply', async () => {
    const { config } = await build({ MIGRATION_APP_BACKEND_TIMEOUT_MS: '1e4', MIGRATION_APP_BACKEND_MAX_ATTEMPTS: '30s', MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '12.5', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '0x10' });
    const warns = logs.filter((l) => l.level === 'warn' && l.msg.includes('migration.backend.config.invalid'));
    dump('H7', { applied: { timeoutMs: config.timeoutMs, maxAttempts: config.maxAttempts, retryBaseDelayMs: config.retryBaseDelayMs, retryMaxDelayMs: config.retryMaxDelayMs }, invalidWarns: warns.map((w) => JSON.parse(w.msg)) });
    expect(config.timeoutMs).toBe(15000);
    expect(config.maxAttempts).toBe(4);
    expect(config.retryBaseDelayMs).toBe(500);
    expect(config.retryMaxDelayMs).toBe(8000);
    expect(warns).toHaveLength(4);
  });
});
