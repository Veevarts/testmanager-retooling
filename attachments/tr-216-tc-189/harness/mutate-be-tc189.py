#!/usr/bin/env python3
"""Mutaciones del backend de IM-1313 ("#411") sobre main. Cada una se aplica, se corre jest de
src/csm/tasks y el banco SQL (scripts/csm-os/verify-task-suggestions-local.ts) contra una base local
desechable, y se restaura con git checkout. Nada se comitea."""
import subprocess, pathlib, re, sys, os
BE = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2]); DB = sys.argv[3]; OUT.mkdir(parents=True, exist_ok=True)
RD = "src/csm/tasks/infrastructure/adapters/aurora-task-read.repository.ts"
SG = "src/csm/tasks/infrastructure/adapters/aurora-task-suggestion.repository.ts"
PP = "src/csm/tasks/domain/suggestion-pool-page.ts"
CT = "src/csm/tasks/infrastructure/entrypoints/api/tasks.controller.ts"
DT = "src/csm/tasks/infrastructure/entrypoints/api/dtos/tasks-query.dto.ts"
FILES = [RD, SG, PP, CT, DT]
def after(marker, old, new):
    def f(s):
        i = s.index(marker); j = s.index(old, i)
        return s[:j] + new + s[j + len(old):]
    return f
def rep(old, new, count=1):
    def f(s):
        assert s.count(old) == count, (old[:50], s.count(old))
        return s.replace(old, new)
    return f
M = [
 ("BASE", "sin cambios (control)", []),
 ("B1", "NULL deja de ser elegible: IS NOT TRUE -> = false", [(RD, rep("`a.on_implementation IS NOT TRUE`", "`a.on_implementation = false`"))]),
 ("B2", "el pool de una cuenta (accountId) tambien oculta las de implementacion", [(PP, rep("options.accountId === undefined &&", "true &&"))]),
 ("B3", "el contador de ocultas cuenta tambien las NULL", [(RD, rep("AND a.on_implementation IS TRUE`,", "AND a.on_implementation IS NOT FALSE`,"))]),
 ("B4", "el controlador acepta un cursor emitido bajo el otro filtro", [(CT, rep("decoded.excludesOnImplementation !==\n                poolExcludesOnImplementation(query)", "false"))]),
 ("B5", "includeOnImplementation=1 se acepta como true", [(DT, after("IM-1313: My Day", "value === 'true' ? true", "value === 'true' || value === '1' ? true"))]),
 ("B6", "el lote servido deja de filtrar al leer", [(RD, rep("               AND ${NOT_ON_IMPLEMENTATION}\n             ORDER BY cta.score DESC NULLS LAST, cta.created_at, cta.id`", "             ORDER BY cta.score DESC NULLS LAST, cta.created_at, cta.id`"))]),
 ("B7", "la generacion vuelve a ver pendientes y candidatas de cuentas en implementacion", [(SG, rep("            AND cta.suggestion_batch_id IS NOT NULL\n            AND ${NOT_ON_IMPLEMENTATION}", "            AND cta.suggestion_batch_id IS NOT NULL")), (SG, rep("            AND cta.suggestion_batch_id IS NULL\n            AND ${NOT_ON_IMPLEMENTATION}", "            AND cta.suggestion_batch_id IS NULL"))]),
 ("B8", "la generacion vuelve a ver las senales de salud y email de esas cuentas", [(SG, rep("                AND ${NOT_ON_IMPLEMENTATION}\n", "")), (SG, rep("          WHERE a.csm_owner_id = :ownerId\n            AND ${NOT_ON_IMPLEMENTATION}\n", "          WHERE a.csm_owner_id = :ownerId\n"))]),
]
def run(cmd, **kw): return subprocess.run(cmd, cwd=BE, capture_output=True, text=True, **kw)
clean = lambda t: re.sub(r"\x1b\[[0-9;]*m", "", t)
summary = []
for key, desc, edits in M:
    run(["git", "checkout", "--", *FILES])
    try:
        for path, fn in edits:
            p = BE / path; p.write_text(fn(p.read_text()))
    except Exception as e:
        summary.append((key, desc, f"NO APLICADA {e}", [], [])); continue
    diff = run(["git", "diff", "--", *FILES]).stdout
    j = run(["npx", "jest", "src/csm/tasks"], env={**os.environ, "CI": "true"})
    jl = clean(j.stdout + j.stderr)
    b = run(["npm", "run", "csm-os:tasks:verify:local"], env={**os.environ, "DATABASE_URL": DB})
    bl = clean(b.stdout + b.stderr)
    (OUT / f"{key}.log").write_text(f"# {key}: {desc}\n\n## diff\n{diff}\n## jest\n{jl[-6000:]}\n## banco\n{bl}")
    jt = [l.strip() for l in jl.splitlines() if l.strip().startswith("Tests:")]
    jfail = sorted({l.strip()[2:].strip() for l in jl.splitlines() if l.strip().startswith("●") and "›" in l})[:8]
    bt = [l.strip() for l in bl.splitlines() if re.search(r"\d+/\d+ checks passed", l)]
    bfail = [l.strip()[5:] for l in bl.splitlines() if l.strip().startswith("FAIL ")][:8]
    summary.append((key, desc, f"jest: {jt[-1] if jt else '?'} | banco: {bt[-1] if bt else '?'}", jfail, bfail))
run(["git", "checkout", "--", *FILES])
with open(OUT / "resumen.txt", "w") as f:
    for key, desc, res, jf, bf in summary:
        f.write(f"{key} | {desc} | {res}\n")
        for t in jf: f.write(f"    jest rojo:  {t}\n")
        for t in bf: f.write(f"    banco rojo: {t}\n")
print((OUT / "resumen.txt").read_text())
print("git status:", run(["git", "status", "--short"]).stdout or "limpio")
