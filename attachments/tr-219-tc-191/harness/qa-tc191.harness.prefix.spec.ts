/**
 * TR-219 / TC-191 (IM-1202) - QA harness, PRE-FIX variant (parent of the #173 merge). Same server and wiring.
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

describe('TC-191 harness on the PRE-FIX parent', () => {
  it('P1 AC4 pre-fix: persistent 403 -> how many attempts, and is there any ERROR carrying run id + 403?', async () => {
    route = () => 'deny';
    const { useCase } = await build({});
    const t0 = Date.now();
    let threw: string | null = null;
    let result: any = null;
    try { result = await run(useCase, [MigrationObject.OPPORTUNITY_MEMBERSHIP], [file(MigrationObject.OPPORTUNITY_MEMBERSHIP, 1), file(MigrationObject.OPPORTUNITY_MEMBERSHIP, 2)]); } catch (e: any) { threw = String(e?.message || e); }
    const put = hits.filter((h) => h.kind === 'files');
    const patch = hits.filter((h) => h.kind === 'status');
    const errors = logs.filter((l) => l.level === 'error');
    dump('P1', { elapsed: Date.now() - t0, putCount: put.length, patchCount: patch.length, patchBody: patch[0]?.body, errorEvents: errors.map((e) => { try { const j = JSON.parse(e.msg); return { event: j.event, httpStatus: j.httpStatus, runId: j.migrationRunId }; } catch { return e.msg.slice(0, 160); } }), warns: logs.filter((l) => l.level === 'warn').map((w) => w.msg.slice(0, 200)), undeliveredCount: errors.filter((l) => l.msg.includes('terminal.callback.undelivered')).length, result: result && { statusUpdateSuccess: result.statusUpdateSuccess }, threw });
    expect(true).toBe(true);
  }, 60000);

  it('P2 pre-fix: a hung backend - does the status callback ever give up?', async () => {
    route = () => 'hang';
    const { port } = await build({});
    const t0 = Date.now();
    const outcome = await Promise.race([
      (port as any).updateStatus({ clientId: CLIENT, migrationRunId: RUN, status: 'CSV_DONE' }).then((r: any) => ({ settled: true, r })),
      new Promise((r) => setTimeout(() => r({ settled: false, note: 'still pending after 5000 ms: no per-request deadline' }), 5000)),
    ]);
    dump('P2', { outcome, elapsed: Date.now() - t0, attemptsSeenByServer: hits.length });
    expect(true).toBe(true);
  }, 30000);
});
