#!/usr/bin/env python3
"""Mutaciones de QA IM-1207 v4 (TR-211): reintroduce cada defecto corregido tras TR-209 y comprueba que algo lo detecta.
Cada runner con base usa una copia nueva de la plantilla csmos_tpl (recien migrada), asi un test no hereda filas de otro."""
import subprocess, os, pathlib, time, re, sys
S = pathlib.Path(__file__).parent
BE, FE = S / "be", S / "fe"
LAM = BE / "infra/sam/csm-os/sync-orchestrator/lambdas"
LOG = S / "logs3" / "mutaciones"; LOG.mkdir(parents=True, exist_ok=True)
PGU = os.environ["QA_PG_URL"]  # p. ej. postgres://postgres:<password>@localhost:<puerto> del contenedor local
NODE = ["fnm", "exec", "--using=20"]
W = "infra/sam/csm-os/sync-orchestrator/lambdas/src/handlers/evaluate-playbooks-worker.ts"
R = "src/csm/playbooks/infrastructure/adapters/aurora-playbook.repository.ts"
G = "src/shared/auth/cognito-groups.guard.ts"
FEV = "src/features/csm/api/playbookEvaluations.ts"

def fresh(db):
    subprocess.run(["docker", "exec", "qa-tc186-pg", "psql", "-U", "postgres", "-q", "-c", f"DROP DATABASE IF EXISTS {db}", "-c", f"CREATE DATABASE {db} TEMPLATE csmos_tpl"], check=True, capture_output=True)
    return f"{PGU}/{db}"

RUN = {
 "lam_worker": lambda: (LAM, NODE + ["npx", "jest", "--ci", "src/handlers/__tests__/evaluate-playbooks-worker.test.ts"], {}),
 "lam_pg": lambda: (LAM, NODE + ["npx", "jest", "--ci", "--runInBand", "pg.integration"], {"CSM_DB_LOCAL_URL": fresh("csmos_mut_lam"), "CSM_DB_REQUIRED": "1"}),
 "bench": lambda: (BE, NODE + ["npm", "run", "csm-os:playbooks:simulate"], {"SIM_DATABASE_URL": fresh("csmos_mut_sim"), "SIM_ALLOW_DESTRUCTIVE": "true"}),
 "root_pb": lambda: (BE, NODE + ["npx", "jest", "--ci", "--runInBand", "src/csm/playbooks", "src/csm/shared/db/local-pg.integration.spec.ts", "src/shared/auth"], {"CSM_DB_LOCAL_URL": fresh("csmos_mut_root"), "LOCAL_DEV_MODE": "true"}),
 "fe_csm": lambda: (FE, NODE + ["npx", "vitest", "run", "src/features/csm"], {}),
 "fe_contract": lambda: (FE, NODE + ["npm", "run", "contract:check"], {"BACKEND_REPO": str(BE)}),
}
M = [
 ("BASE-sin-cambios", None, None, None, None, list(RUN)),
 ("MB1-limite-vuelve-a-published_at", BE, W, "extract(epoch FROM pv.first_evaluating_at)::float8 AS first_evaluating_epoch",
  "extract(epoch FROM pv.published_at)::float8 AS first_evaluating_epoch", ["lam_worker", "lam_pg", "bench"]),
 ("MB2-abierto-si-no-lee-el-limite", BE, W, "if (unreadable || occurredEpoch < switchedOnEpoch) {",
  "if (!unreadable && occurredEpoch < switchedOnEpoch) {", ["lam_worker"]),
 ("MB3-sello-no-es-de-escritura-unica", BE, R, "SET first_evaluating_at = COALESCE(pv.first_evaluating_at, now())",
  "SET first_evaluating_at = now()", ["root_pb"]),
 ("MB4-republicar-no-sella", BE, R, "            await this.stampFirstEvaluating(tx, playbookId);\n",
  "            void playbookId;\n", ["root_pb"]),
 ("MB5-cambio-de-estado-no-sella", BE, R, "            await this.stampFirstEvaluating(tx, id);\n",
  "            void id;\n", ["root_pb"]),
 ("MB6-autoria-a-csm-managers", BE, G, "export const ADMIN_GROUP = 'admin';", "export const ADMIN_GROUP = 'csm-managers';", ["root_pb"]),
 ("MF1-log-vuelve-a-la-condicion", FE, FEV, "const refusedTheEvent = !trigger.passed && explanation !== null;",
  "const refusedTheEvent = false;", ["fe_csm"]),
 ("MF2-guarda-vuelve-a-needed-measured", FE, FEV, "      expected: null,\n      actual: null,\n    });",
  "      expected: (guard.detail as any)?.policy ?? null,\n      actual: (guard.detail as any)?.subjectKey ?? null,\n    });", ["fe_csm"]),
 ("MX1-motor-cambia-la-frase", BE, W, "`before this play was switched on, so the play was not ` +",
  "`before this play went live, so the play was not ` +", ["fe_contract", "fe_csm", "lam_worker"]),
]
only = set(sys.argv[1:])
summary = []
for name, repo, rel, old, new, runs in M:
    if only and name not in only: continue
    src = None
    if repo:
        path = repo / rel; src = path.read_text()
        assert src.count(old) == 1, f"{name}: patron {src.count(old)} veces"
        path.write_text(src.replace(old, new))
    try:
        res = []
        for label in runs:
            cwd, cmd, extra = RUN[label]()
            t0 = time.time()
            p = subprocess.run(cmd, cwd=cwd, env=dict(os.environ, CI="true", **extra), capture_output=True, text=True)
            out = re.sub(r"\x1b\[[0-9;]*m", "", p.stdout + p.stderr)
            (LOG / f"{name}__{label}.log").write_text(out)
            tail = [l.strip() for l in out.splitlines() if l.strip().startswith(("Tests:", "Test Suites:", "Test Files", "Tests  ", "ALL GREEN", "FAILED", "Backend contract", "Contract"))]
            fails = sorted({l.strip()[:150] for l in out.splitlines() if l.strip().startswith(("● ", "× ", "FAIL ")) and "Console" not in l})[:5]
            res.append(f"{label}: exit={p.returncode} ({time.time()-t0:.0f}s) {' | '.join(tail[-3:])}\n        fallos: {fails}")
        zero = any(re.search(r"Tests:\s+0 total|Tests\s+0 ", r) for r in res)
        det = any(" exit=0 " not in r for r in res)
        verdict = ("BASE " + ("VERDE" if not det else "ROJA")) if name.startswith("BASE") else ("COMPILA MAL (no cuenta)" if zero else ("DETECTADA" if det else "NO DETECTADA"))
        summary.append(f"{name}: {verdict}\n    " + "\n    ".join(res)); print(summary[-1], flush=True)
    finally:
        if repo:
            subprocess.run(["git", "checkout", "--", rel], cwd=repo, check=True)
            assert (repo / rel).read_text() == src
(LOG / ("resumen.txt" if not only else "resumen-parcial.txt")).write_text("\n".join(summary) + "\n")
