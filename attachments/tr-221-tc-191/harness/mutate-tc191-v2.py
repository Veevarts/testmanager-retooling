#!/usr/bin/env python3
"""TR-221 / TC-191 v2 (IM-1202): mutations of ETL #190 and BE #417/#419/#422/#424 against their PR specs.
Usage: mutate-tc191-v2.py <etl-clone> <be-clone> <out.txt>"""
import os, re, subprocess, sys, pathlib
etl, be, out = map(pathlib.Path, sys.argv[1:4])
U = 'src/data-migration/application/use-cases/'
ETL_SPECS = [U + f for f in ['run-migration.use-case.spec.ts', 'run-migration.heartbeat.spec.ts', 'run-migration.stop-policy.spec.ts', 'run-migration.tracker.spec.ts', 'run-migration.wiring.spec.ts']]
BU = 'src/migration/application/use-cases/'
BE_SPECS = [BU + 'run-migration-run-watchdog.use-case.spec.ts', BU + 'run-migration-run-watchdog.settle-parity.spec.ts', BU + 'run-migration-run-watchdog.alert-failure.spec.ts', BU + 'list-migration-files.use-case.spec.ts', 'src/migration/domain/model/migration-object.entity.spec.ts', 'src/migration/infrastructure/entrypoints/etl/etl-migration.late-report.spec.ts', 'src/migration/infrastructure/persistence/dynamodb/migration-runs.dynamodb.repository.spec.ts', 'src/migration/application/services/migration-run-watchdog-alert.spec.ts']
M = [
 ('X1', etl, 'src/data-migration/application/use-cases/run-migration.stop-policy.ts', "      return (await reconnect()) ? undefined : 'database-unavailable';\n    }\n\n    return undefined;", "      return (await reconnect()) ? undefined : 'database-unavailable';\n    }\n\n    return 'database-unavailable';", 'cualquier fallo de objeto para la corrida (sin aislamiento)'),
 ('X2', etl, U + 'run-migration.use-case.ts', "          if (ready) {\n            await this.reportObjectFiles(run, ready);\n          }\n", '', 'no informa cada objeto al terminar'),
 ('X3', etl, U + 'run-migration.use-case.ts', 'const reportedStatus = everyObjectDelivered', 'const reportedStatus = true', 'COMPLETED aunque falle un objeto'),
 ('X4', etl, U + 'run-migration.heartbeat.ts', 'if (millisSinceProgress > this.options.stallThresholdMs) {', 'if (false) {', 'el latido sigue aunque la corrida este parada'),
 ('X5', etl, U + 'run-migration.stop-policy.ts', 'this.queryTimeoutsSinceSuccess >= this.maxConsecutiveQueryTimeouts', 'this.queryTimeoutsSinceSuccess >= 1', 'un solo timeout para la corrida'),
 ('Y1', be, BU + 'run-migration-run-watchdog.use-case.ts', 'run.lastActivityAt ? Date.parse(run.lastActivityAt) : NaN,', 'NaN,', 'ignora el latido / lastActivityAt'),
 ('Y2', be, BU + 'run-migration-run-watchdog.use-case.ts', '...objects.map(objectActivityMs),', '', 'ignora la actividad de los objetos'),
 ('Y3', be, BU + 'run-migration-run-watchdog.use-case.ts', 'return now - activityMs > thresholdMs;', 'return false;', 'nunca considera una corrida caducada'),
 ('Y4', be, BU + 'run-migration-run-watchdog.use-case.ts', 'if (failedRuns.length === 0) {', 'if (true) {', 'no envia la alerta'),
 ('Y5', be, 'src/migration/domain/model/migration-object.entity.ts', "return settledStatusFromFiles(object.files) === 'COMPLETED';", 'return (object.files ?? []).length > 0;', 'objeto parcial descargable'),
 ('Y6', be, 'src/migration/infrastructure/persistence/dynamodb/migration-runs.dynamodb.repository.ts', "' AND (attribute_not_exists(#lastActivityAt) OR #lastActivityAt < :inactiveBefore)'", "''", 'sin guarda contra actividad tardia al marcar FAILED'),
]
lines = []
for key, repo, rel, old, new, what in M:
    p = repo / rel; src = p.read_text(); n = src.count(old)
    if n != 1:
        lines.append(f'{key}  NO APLICADA ({n})  {what}'); continue
    p.write_text(src.replace(old, new))
    try:
        if repo == etl: cmd = ['fnm', 'exec', '--using=22', 'npx', 'jest', '--forceExit', *ETL_SPECS]
        else: cmd = ['fnm', 'exec', '--using=20', 'npx', 'jest', *BE_SPECS]
        r = subprocess.run(cmd, cwd=repo, capture_output=True, text=True)
        txt = re.sub(r'\x1b\[[0-9;]*m', '', r.stdout + r.stderr)
        summ = [l.strip() for l in txt.splitlines() if l.strip().startswith('Tests:')]
        fails = [l.strip() for l in txt.splitlines() if l.strip().startswith('✕')][:2]
        lines.append(f'{key}  {"DETECTADA" if r.returncode else "SOBREVIVE":9}  {what}  | {summ[-1] if summ else "?"}')
        lines += [f'      {f[:150]}' for f in fails]
    finally:
        subprocess.run(['git', 'checkout', '--', rel], cwd=repo, check=True)
out.write_text('\n'.join(lines) + '\n'); print('\n'.join(lines))
