#!/usr/bin/env python3
"""Mutaciones de QA IM-1245: reintroduce un error plausible por regla y comprueba que alguna suite lo detecta."""
import subprocess, os, pathlib, time, sys
S = pathlib.Path(sys.argv[1])
BE, FE = S / "im-1207" / "be", S / "im-1207" / "fe"
LOG = S / "im-1245" / "logs" / "mutaciones"; LOG.mkdir(parents=True, exist_ok=True)
NODE = ["fnm", "exec", "--using=20"]
VIEW = "src/csm/workspace/domain/account-metrics-view.ts"
SVC = "src/csm/workspace/application/workspace.service.ts"
SF = "src/features/csm/utils/metricServerFilters.ts"
MF = "src/features/csm/utils/metricFilters.ts"
API = "src/features/csm/api/workspace.ts"
COPY = "src/features/csm/utils/metricComparisonCopy.ts"
BE_RUN = [("jest-workspace", BE, NODE + ["npx", "jest", "--ci", "src/csm/workspace"])]
FE_RUN = [("vitest-csm", FE, NODE + ["npx", "vitest", "run", "src/features/csm"])]
M = [
 ("M01-sin-regla-primera-fila", BE, VIEW, "firstRow === null ? [] : reportedMonths.filter((m) => m >= firstRow),", "firstRow === null ? [] : [...reportedMonths],", BE_RUN),
 ("M02-overview-sin-horizonte-18m", BE, SVC, "const recent = allPoints.filter(\n            (p) => p.periodStart === null || p.periodStart >= cutoff,\n        );", "const recent = allPoints.filter(\n            (p) => p.periodStart === null || cutoff !== '',\n        );", BE_RUN),
 ("M03-sin-clasificar-toma-ultimo-mes", BE, VIEW, "const single = months.length === 1 ? byMonth.get(months[0]) : undefined;", "const single = byMonth.get(months[months.length - 1]);", BE_RUN),
 ("M04-nivel-toma-primer-mes", BE, VIEW, "for (let i = reportedMonths.length - 1; i >= 0; i--) {", "for (let i = 0; i < reportedMonths.length; i++) {", BE_RUN),
 ("M05-trimestre-cortado-como-Q", BE, VIEW, "if (!cut && groupBy === 'quarter') {", "if (groupBy === 'quarter') {", BE_RUN),
 ("M06-chargebacks-won-a-other", BE, VIEW, "    number_of_chargebacks_won: 'payments_risk',\n", "", BE_RUN),
 ("M07-trimestre-siempre-ofrecido", BE, VIEW, "if (quarterStart(from) !== quarterStart(to)) out.push('quarter');", "out.push('quarter');", BE_RUN),
 ("M08-sin-filtros-da-vista-filtrada", BE, VIEW, "return Object.values(input).some((v) => v !== undefined);", "return Object.values(input).length >= 0;", BE_RUN),
 ("M09-pct-con-cobertura-incompleta", BE, VIEW, "const fair = complete(primary.coverage) && complete(secondary.coverage);", "const fair = complete(primary.coverage) || complete(secondary.coverage);", BE_RUN),
 ("M10-fe-default-sin-parametros", FE, SF, '  query.compare = "previous_period";\n  if (filters.compare === "none") {', '  if (filters.compare !== "previous_period") query.compare = "previous_period";\n  if (filters.compare === "none") {', FE_RUN),
 ("M11-fe-no-reescribe-comparacion-rechazada", FE, SF, "  if (sent === filters.compare) return filters;\n  return { ...filters, compare: sent", "  if (sent !== null) return filters;\n  return { ...filters, compare: sent", FE_RUN),
 ("M12-fe-400-como-error-generico", FE, API, "if (response.status === 400) {", "if (response.status === 499) {", FE_RUN),
 ("M13-fe-aviso-frescura-a-3-meses", FE, MF, "isStale: monthsBehind > 1 }", "isStale: monthsBehind > 2 }", FE_RUN),
 ("M14-fe-sin-motivo-no-comparado", FE, COPY, "  if (a && a.months < a.of) {\n    return `Not compared: ${periodLabel", "  if (a && a.months < 0) {\n    return `Not compared: ${periodLabel", FE_RUN),
 ("M15-fe-presets-anclados-a-hoy", FE, SF, "anchor ? { from: addMonths(anchor, -(n - 1)), to: anchor } : \"needs-anchor\";", "anchor ? { from: addMonths(now, -(n - 1)), to: now } : \"needs-anchor\";", FE_RUN),
]
only = set(sys.argv[2:])
summary = []
for name, repo, rel, old, new, runs in M:
    if only and name not in only: continue
    path = repo / rel; src = path.read_text()
    assert src.count(old) == 1, f"{name}: patron encontrado {src.count(old)} veces"
    path.write_text(src.replace(old, new))
    try:
        res = []
        for label, cwd, cmd in runs:
            t0 = time.time()
            p = subprocess.run(cmd, cwd=cwd, env=dict(os.environ, CI="true"), capture_output=True, text=True)
            out = p.stdout + p.stderr
            (LOG / f"{name}__{label}.log").write_text(out)
            import re
            clean = re.sub(r"\x1b\[[0-9;]*m", "", out)
            tail = [l.strip() for l in clean.splitlines() if l.strip().startswith(("Tests:", "Tests ", "Test Files", "Test Suites:"))]
            failing = sorted({l.split("›")[0].strip() for l in clean.splitlines() if l.strip().startswith(("●", "FAIL", "×"))})[:4]
            res.append(f"{label}: exit={p.returncode} ({time.time()-t0:.0f}s) {' | '.join(tail[-2:])}\n      primeros fallos: {failing}")
        compile_err = any("0 total" in r for r in res)
        det = any(" exit=0 " not in r for r in res)
        verdict = "COMPILA MAL (no cuenta)" if compile_err else ("DETECTADA" if det else "NO DETECTADA")
        summary.append(f"{name}: {verdict}\n    " + "\n    ".join(res))
        print(summary[-1], flush=True)
    finally:
        subprocess.run(["git", "checkout", "--", rel], cwd=repo, check=True)
    assert (repo / rel).read_text() == src
(LOG / ("resumen.txt" if not only else "resumen-parcial.txt")).write_text("\n".join(summary) + "\n")
