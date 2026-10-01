/**
 * TR-221 / TC-191 v2 (IM-1202) - QA harness v2 (after ETL #190), NOT part of the PR.
 *
 * Real code path: MigrationAppBackendModule (config factory from env) -> MigrationAppBackendAdapter (real fetch:
 * status, files and the new heartbeat callback) and the real RunHeartbeat class from #190. The backend is a real
 * HTTP server on 127.0.0.1 that answers like the VPC endpoint did (403 ForbiddenException), like API Gateway (200),
 * 503 or not at all, per path. The run flow itself (per-object isolation, immediate reporting) is covered by the #190
 * specs and by the dev runs of TR-221.
 */
import { MigrationAppBackendModule } from '@data-migration/infrastructure/destination/migration-app-backend/migration-app-backend.module';
import { MIGRATION_BACKEND_PORT } from '@data-migration/application/ports/migration-backend.port';
import { UpdateMigrationObjectFilesUseCase } from '@data-migration/application/use-cases/update-migration-object-files.use-case';
import { UpdateMigrationStatusUseCase } from '@data-migration/application/use-cases/update-migration-status.use-case';
import { RunHeartbeat } from '@data-migration/application/use-cases/run-migration.heartbeat';
import { MigrationObject } from '@data-migration/domain/enums/migration-object.enum';
import { ConfigModule } from '@nestjs/config';
import { Logger } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as fs from 'fs';
import * as http from 'http';

type Mode = 'deny' | 'ok' | 'hang' | '503';
type Kind = 'files' | 'status' | 'heartbeat';
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
      const kind: any = m ? 'files' : /\/heartbeat$/.test(req.url!) ? 'heartbeat' : 'status';
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
  return { port, config: (port as any).config };
};

const file = (obj: MigrationObject, part: number) => ({
  objectName: `${obj.toLowerCase()}_part${part}`,
  sourceObjectName: obj,
  fileName: `${CLIENT}/migration/${RUN}/objects/${obj.toLowerCase()}_part${part}.csv`,
  etag: `etag-${obj}-${part}`,
  size: 100 * part,
  contentType: 'text/csv',
});


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

describe('TC-191 v2 harness (real adapter + real HTTP, ETL #190)', () => {
  it('A1 AC4: a persistent 403 on the status callback is retried with growing backoff and logged with run id and HTTP status', async () => {
    route = () => 'deny';
    const { port, config } = await build({});
    const r = await (port as any).updateStatus({ clientId: CLIENT, migrationRunId: RUN, status: 'CSV_DONE', summary: { totalObjects: 1, completed: 1, failed: 0 } });
    const patch = hits.filter((h) => h.kind === 'status');
    const errs = logs.filter((l) => l.level === 'error').map((l) => { try { return JSON.parse(l.msg); } catch { return { raw: l.msg.slice(0, 120) }; } });
    dump('A1', { config: { ...config, apiKey: '<omitted>', baseUrl: '<local>' }, attempts: patch.length, gapsMs: gaps(patch), result: r, errors: errs.map((e: any) => ({ event: e.event, httpStatus: e.httpStatus, attempts: e.attempts, runId: e.migrationRunId })) });
    expect(patch).toHaveLength(4);
    const g = gaps(patch); expect(g[0]).toBeGreaterThanOrEqual(450); expect(g[1]).toBeGreaterThanOrEqual(950); expect(g[2]).toBeGreaterThanOrEqual(1950);
    expect(r.success).toBe(false);
    expect(errs.some((e: any) => e.httpStatus === 403 && e.migrationRunId === RUN)).toBe(true);
  }, 30000);

  it('HB1 AC5: heartbeats go out while the run progresses and stop once it stalls', async () => {
    route = () => 'ok';
    const { port } = await build({});
    let lastProgress = Date.now();
    const hb = new RunHeartbeat({ intervalMs: 100, stallThresholdMs: 450, millisSinceProgress: () => Date.now() - lastProgress, send: () => (port as any).heartbeat({ clientId: CLIENT, migrationRunId: RUN }), logger: new Logger('QaHeartbeat'), logContext: { clientId: CLIENT, migrationRunId: RUN } });
    const t0 = Date.now();
    hb.start();
    const ticker = setInterval(() => { if (Date.now() - t0 < 600) lastProgress = Date.now(); }, 50); // progress for 600 ms, then stall
    await new Promise((r) => setTimeout(r, 1800));
    clearInterval(ticker); await hb.stop();
    const beats = hits.filter((h) => h.kind === 'heartbeat').map((h) => h.t - t0);
    const stallLogs = logs.filter((l) => /stall/i.test(l.msg)).map((l) => l.msg.slice(0, 200));
    dump('HB1', { beatsAtMs: beats, lastBeatMs: beats[beats.length - 1], stallLogs, apiKeyOnEveryBeat: hits.filter((h) => h.kind === 'heartbeat').every((h) => h.apiKeyPresent) });
    expect(beats.length).toBeGreaterThanOrEqual(4);
    expect(beats[beats.length - 1]).toBeLessThan(1200); // nothing after the stall threshold (600 + 450 + one interval)
    expect(stallLogs.length).toBeGreaterThanOrEqual(1);
  }, 30000);

  it('HB2 AC5: a refused heartbeat is one attempt per tick (no retry ladder) and does not throw', async () => {
    route = (kind) => (kind === ('heartbeat' as any) ? '503' : 'ok');
    const { port } = await build({});
    const r = await (port as any).heartbeat({ clientId: CLIENT, migrationRunId: RUN });
    dump('HB2', { attempts: hits.filter((h) => h.kind === 'heartbeat').length, result: r });
    expect(hits.filter((h) => h.kind === 'heartbeat')).toHaveLength(1);
    expect(r.success).toBe(false);
    expect(r.httpStatus).toBe(503);
  }, 30000);

  it('H5 timeout: a hung backend is cut by the per-attempt deadline and still retried', async () => {
    route = () => 'hang';
    const { port } = await build({ MIGRATION_APP_BACKEND_TIMEOUT_MS: '300', MIGRATION_APP_BACKEND_MAX_ATTEMPTS: '3', MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '20', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '40' });
    const t0 = Date.now();
    const r = await (port as any).updateStatus({ clientId: CLIENT, migrationRunId: RUN, status: 'CSV_DONE' });
    dump('H5', { attemptsSeenByServer: hits.length, success: r.success, elapsed: Date.now() - t0 });
    expect(hits).toHaveLength(3); expect(r.success).toBe(false); expect(Date.now() - t0).toBeLessThan(3000);
  }, 30000);

  it('H6 security: neither the API key nor the id-bearing URL reaches the logs (status, files, heartbeat)', async () => {
    route = () => 'deny';
    const { port } = await build({ MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '20', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '40' });
    await (port as any).updateStatus({ clientId: CLIENT, migrationRunId: RUN, status: 'FAILED' });
    await (port as any).updateObjectFiles({ clientId: CLIENT, migrationRunId: RUN, objectName: 'CONTACT', files: [{ id: 'f1', part: 'contact_part1', name: 'contact_part1.csv', status: 'COMPLETED', location: `${CLIENT}/migration/${RUN}/objects/contact_part1.csv`, size: 10 }] });
    await (port as any).heartbeat({ clientId: CLIENT, migrationRunId: RUN });
    const all = logs.map((l) => l.msg).join('\n');
    dump('H6', { lines: logs.length, keyLeaks: all.split(API_KEY).length - 1, pathLeaks: (all.match(/\/api\/etl\/clients\//g) || []).length, apiKeySentOnEveryRequest: hits.every((h) => h.apiKeyPresent) });
    expect(all).not.toContain(API_KEY); expect(all).not.toMatch(/\/api\/etl\/clients\//); expect(hits.every((h) => h.apiKeyPresent)).toBe(true);
  }, 30000);

  it('H7 config: malformed values are rejected with a WARN and the defaults apply', async () => {
    const { config } = await build({ MIGRATION_APP_BACKEND_TIMEOUT_MS: '1e4', MIGRATION_APP_BACKEND_MAX_ATTEMPTS: '30s', MIGRATION_APP_BACKEND_RETRY_BASE_DELAY_MS: '12.5', MIGRATION_APP_BACKEND_RETRY_MAX_DELAY_MS: '0x10' });
    const warns = logs.filter((l) => l.level === 'warn' && l.msg.includes('config.invalid'));
    dump('H7', { applied: { timeoutMs: config.timeoutMs, maxAttempts: config.maxAttempts, retryBaseDelayMs: config.retryBaseDelayMs, retryMaxDelayMs: config.retryMaxDelayMs, heartbeatIntervalMs: config.heartbeatIntervalMs }, invalidWarns: warns.length });
    expect(config.timeoutMs).toBe(15000); expect(config.maxAttempts).toBe(4); expect(warns.length).toBeGreaterThanOrEqual(4);
  });
});
