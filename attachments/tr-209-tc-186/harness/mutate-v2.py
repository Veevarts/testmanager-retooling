#!/usr/bin/env python3
"""Mutaciones de TR-204 v2 (IM-1207): reintroduce cada defecto corregido y comprueba que alguna suite lo detecta."""
import subprocess, os, pathlib, time

S = pathlib.Path(__file__).parent
BE, FE, LOG = S / "be", S / "fe", S / "logs2" / "mutaciones"
LOG.mkdir(parents=True, exist_ok=True)
LAM = BE / "infra/sam/csm-os/sync-orchestrator/lambdas"
PG = "postgres://<pg-local-desechable>/csmos"
PG_ISO = "postgres://<pg-local-desechable>/csmos_iso"
NODE = ["fnm", "exec", "--using=20"]

WORKER = "infra/sam/csm-os/sync-orchestrator/lambdas/src/handlers/evaluate-playbooks-worker.ts"
CATALOG = "src/csm/playbooks/application/catalog.service.ts"
VALIDATOR = "src/csm/playbooks/domain/definition-validator.ts"
FE_EVAL = "src/features/csm/api/playbookEvaluations.ts"
FE_LIB = "src/features/csm/pages/PlaybookLibraryPage.tsx"

NO_DATA_PUSH = ("issues.push({\n                    path: 'trigger.catalogKey',\n                    message:\n"
                "                        `'${key}' has no data behind it: nothing in the tables it ` +")

MUTATIONS = [
    ("M1-F1-sin-guarda-predates", BE, WORKER,
     "if (unreadable || occurredEpoch < publishedEpoch) {",
     "if (false && (unreadable || occurredEpoch < publishedEpoch)) {",
     [("lambdas-worker", LAM, NODE + ["npx", "jest", "--ci", "src/handlers/__tests__/evaluate-playbooks-worker.test.ts"], {}),
      ("lambdas-pg", LAM, NODE + ["npx", "jest", "--ci", "--runInBand", "manual-enrolment-pg", "step-authoring-pg"],
       {"CSM_DB_LOCAL_URL": PG, "CSM_DB_REQUIRED": "1"}),
      ("bench-playbooks", BE, NODE + ["npm", "run", "csm-os:playbooks:simulate"],
       {"SIM_DATABASE_URL": PG, "SIM_ALLOW_DESTRUCTIVE": "true"})]),
    ("M1b-F1-abierto-si-no-lee-fechas", BE, WORKER,
     "if (unreadable || occurredEpoch < publishedEpoch) {",
     "if (!unreadable && occurredEpoch < publishedEpoch) {",
     [("lambdas-worker", LAM, NODE + ["npx", "jest", "--ci", "src/handlers/__tests__/evaluate-playbooks-worker.test.ts"], {})]),
    ("M2-F3-disponibilidad-sin-medir", BE, CATALOG,
     "if (population && population.accounts === 0 && accountsTotal > 0) {",
     "if (false) {",
     [("root-catalog", BE, NODE + ["npx", "jest", "--ci", "src/csm/playbooks/application/catalog.service.spec.ts",
                                   "src/csm/playbooks/application/playbook-authoring.service.spec.ts",
                                   "src/csm/playbooks/infrastructure/adapters/trigger-source-population.integration.spec.ts"],
       {"CSM_DB_LOCAL_URL": PG_ISO, "LOCAL_DEV_MODE": "true"})]),
    ("M3-F3-sin-datos-solo-avisa", BE, VALIDATOR,
     NO_DATA_PUSH,
     NO_DATA_PUSH.replace("path: 'trigger.catalogKey',\n", "path: 'trigger.catalogKey',\n                    severity: 'warning',\n"),
     [("root-authoring", BE, NODE + ["npx", "jest", "--ci", "src/csm/playbooks"],
       {"CSM_DB_LOCAL_URL": PG_ISO, "LOCAL_DEV_MODE": "true"})]),
    ("M4-F2-guarda-con-frase-de-fallo", FE, FE_EVAL,
     "if (sentences) return passed ? sentences.passed : sentences.blocked;",
     "if (sentences) return sentences.blocked;",
     [("vitest-eval", FE, NODE + ["npx", "vitest", "run", "src/features/csm"], {})]),
    ("M5-F4-sin-boton-borrar", FE, FE_LIB,
     "const isOrphan = isOrphanDraft(playbook);",
     "const isOrphan = false;",
     [("vitest-library", FE, NODE + ["npx", "vitest", "run", "src/features/csm/pages/PlaybookLibraryPage.test.tsx"], {})]),
]

summary = []
for name, repo, rel, old, new, runs in MUTATIONS:
    path = repo / rel
    src = path.read_text()
    assert src.count(old) == 1, f"{name}: patron encontrado {src.count(old)} veces"
    path.write_text(src.replace(old, new))
    try:
        results = []
        for label, cwd, cmd, extra in runs:
            env = dict(os.environ, CI="true", **extra)
            t0 = time.time()
            p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
            out = p.stdout + p.stderr
            (LOG / f"{name}__{label}.log").write_text(out)
            tail = [l for l in out.splitlines() if any(k in l for k in ("Tests:", "Test Files", "checks passed", "FAILED", "FAIL —", "checks failed"))]
            results.append(f"{label}: exit={p.returncode} ({time.time()-t0:.0f}s) {' | '.join(tail[-2:])}")
        detected = any(" exit=0 " not in r for r in results)
        summary.append(f"{name}: {'DETECTADA' if detected else 'NO DETECTADA'}\n    " + "\n    ".join(results))
    finally:
        subprocess.run(["git", "checkout", "--", rel], cwd=repo, check=True)
    assert (repo / rel).read_text() == src, f"{name}: no se restauro"

(LOG / "resumen.txt").write_text("\n".join(summary) + "\n")
print("\n".join(summary))
