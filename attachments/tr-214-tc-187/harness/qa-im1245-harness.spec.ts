/**
 * QA IM-1245 (TR de QA, no forma parte del repo): ejecuta el WorkspaceService REAL
 * de este arbol con un repositorio falso que devuelve filas de dev, emulando la
 * ventana SQL de la version (pre: 18 meses exactos; post: 36 meses de calendario).
 */
import { readFileSync, writeFileSync } from 'fs';
import { WorkspaceService } from '@/csm/workspace/application/workspace.service';

const MODE = process.env.QA_MODE as 'pre' | 'post';
const IN = process.env.QA_IN!;
const OUT = process.env.QA_OUT!;
const CALLS: Array<{ name: string; filters?: Record<string, unknown> }> = JSON.parse(
    process.env.QA_CALLS ?? '[{"name":"unfiltered"}]',
);

function windowStart(now: Date): string {
    const y = now.getUTCFullYear();
    const m = now.getUTCMonth();
    if (MODE === 'pre') {
        const idx = y * 12 + m - 18;
        const yy = Math.floor(idx / 12);
        const mm = idx % 12;
        const last = new Date(Date.UTC(yy, mm + 1, 0)).getUTCDate();
        const d = Math.min(now.getUTCDate(), last);
        return `${yy}-${String(mm + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
    }
    const idx = y * 12 + m - 36;
    return `${Math.floor(idx / 12)}-${String((idx % 12) + 1).padStart(2, '0')}-01`;
}

test('qa harness', async () => {
    const points = JSON.parse(readFileSync(IN, 'utf8')) as Array<Record<string, unknown>>;
    const start = windowStart(new Date());
    const visible = points.filter(
        (p) => p.periodStart === null || (p.periodStart as string) >= start,
    );
    const repository = {
        listPrimaryProductMetrics: jest.fn().mockResolvedValue(visible),
    };
    const service = new WorkspaceService(
        repository as never,
        {} as never,
        {} as never,
        {} as never,
        {} as never,
    );
    const out: Record<string, unknown> = { mode: MODE, windowStart: start, rowsVisible: visible.length };
    for (const call of CALLS) {
        try {
            out[call.name] = await (service.getAccountMetrics as (...a: unknown[]) => Promise<unknown>)(
                'acc-qa',
                ...(call.filters ? [call.filters] : []),
            );
        } catch (e) {
            out[call.name] = { error: (e as Error).constructor.name, message: (e as Error).message };
        }
    }
    writeFileSync(OUT, JSON.stringify(out, null, 1));
});
