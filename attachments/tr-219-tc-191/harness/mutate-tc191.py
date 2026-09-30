#!/usr/bin/env python3
"""TR-219 / TC-191 (IM-1202): mutation check of ETL #173 and BE #415.

Each mutation replaces exactly one snippet, runs the PR specs plus the QA harness
(ETL only), records whether anything failed, and restores the file with git
checkout. Usage: mutate-tc191.py <etl-clone> <be-clone> <out.txt>
"""
import subprocess, sys, pathlib

etl, be, out = map(pathlib.Path, sys.argv[1:4])
A = 'src/data-migration/infrastructure/destination/migration-app-backend/'
UC = 'src/data-migration/application/use-cases/run-migration.use-case.ts'
ETL_SPECS = [A + 'migration-app-backend.adapter.spec.ts', A + 'migration-app-backend.module.spec.ts',
             'src/data-migration/application/use-cases/run-migration.use-case.spec.ts',
             'src/data-migration/infrastructure/entrypoints/migration/migration.controller.spec.ts',
             'src/data-migration/qa-tc191.harness.spec.ts']
BE_SPECS = ['src/migration/application/use-cases/settle-migration-objects.use-case.spec.ts',
            'src/migration/application/use-cases/update-migration-object-files.use-case.spec.ts',
            'src/migration/domain/model/migration-object.entity.spec.ts',
            'src/migration/infrastructure/entrypoints/etl/etl-migration.controller.spec.ts']

MUTATIONS = [
    ('E1', etl, A + 'migration-app-backend.adapter.ts', 'const maxAttempts = retriesSuppressed ? 1 : configuredAttempts;', 'const maxAttempts = 1;', 'sin reintentos'),
    ('E2', etl, UC, "event: 'migration.run.terminal.callback.undelivered',", "event: 'migration.run.terminal.callback.x',", 'sin el ERROR undelivered'),
    ('E3', etl, UC, 'const reportedNothing = filesUpdate.succeededObjects.length === 0;', 'const reportedNothing = false;', 'COMPLETED aunque no llegue ningun inventario'),
    ('E4', etl, A + 'migration-app-backend.adapter.ts', '!exemptFromSuppression && this.suppressedRunIds.has(migrationRunId);', 'this.suppressedRunIds.has(migrationRunId);', 'la llamada de estado tambien se suprime'),
    ('E5', etl, A + 'migration-app-backend.adapter.ts', 'return new URL(url).host;', 'return url;', 'registra la URL completa con ids'),
    ('E6', etl, A + 'migration-app-backend.module.ts', "const parsed = POSITIVE_INTEGER.test(trimmed)\n    ? Number.parseInt(trimmed, 10)\n    : Number.NaN;", 'const parsed = Number.parseInt(trimmed, 10);', 'parseInt sin validar (1e4 -> 1)'),
    ('E7', etl, A + 'migration-app-backend.adapter.ts', 'signal: controller.signal,', '', 'sin plazo por intento'),
    ('B1', be, 'src/migration/infrastructure/entrypoints/etl/etl-migration.controller.ts', 'await this.settleObjects(clientId, migrationId);', '', 'el controlador nunca asienta'),
    ('B2', be, 'src/migration/application/use-cases/update-migration-object-files.use-case.ts', 'const status = settledStatusFromFiles(files);', 'const status = undefined as any;', 'el PUT de ficheros no cambia el estado'),
    ('B3', be, 'src/migration/application/use-cases/settle-migration-objects.use-case.ts', "settledStatusFromFiles(object.files) ?? 'FAILED';", 'settledStatusFromFiles(object.files) ?? object.status;', 'objetos sin ficheros se quedan PENDING'),
    ('B4', be, 'src/migration/application/use-cases/settle-migration-objects.use-case.ts', 'if (!UNSETTLED_OBJECT_STATUSES.includes(object.status)) {', 'if (false) {', 'el barrido pisa objetos ya asentados'),
]

lines = []
for key, repo, rel, old, new, what in MUTATIONS:
    p = repo / rel
    src = p.read_text()
    n = src.count(old)
    if n != 1:
        lines.append(f'{key}  NO APLICADA ({n} coincidencias)  {what}')
        continue
    p.write_text(src.replace(old, new))
    try:
        if repo == etl:
            cmd = ['fnm', 'exec', '--using=22', 'npx', 'jest', '--forceExit', *ETL_SPECS]
        else:
            cmd = ['fnm', 'exec', '--using=20', 'npx', 'jest', *BE_SPECS]
        r = subprocess.run(cmd, cwd=repo, capture_output=True, text=True, env={**__import__('os').environ, 'QA_OUT': '/tmp/qa-tc191-mut'})
        summary = [l for l in r.stderr.splitlines() if l.startswith('Tests:')]
        failed = [l.strip() for l in r.stderr.splitlines() if l.strip().startswith('✕')][:3]
        verdict = 'DETECTADA' if r.returncode != 0 else 'SOBREVIVE'
        lines.append(f'{key}  {verdict:9}  {what}  | {summary[-1] if summary else "?"}')
        for f in failed:
            lines.append(f'      {f[:150]}')
    finally:
        subprocess.run(['git', 'checkout', '--', rel], cwd=repo, check=True)

out.write_text('\n'.join(lines) + '\n')
print('\n'.join(lines))
