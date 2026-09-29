#!/usr/bin/env python3
"""Mutaciones de QA IM-1245 v2 (re-test de backend #410 y frontend #216). Cada mutacion reintroduce un
error plausible en el arreglo, corre la suite del area y restaura el fichero con git checkout. Nunca se
comitea. Uso: mutate-v2.py <scratchpad> [nombres...]"""
import subprocess, os, pathlib, time, sys, re
S = pathlib.Path(sys.argv[1])
BE, FE = S / "im-1207" / "be", S / "im-1207" / "fe"
LOG = S / "im-1245" / "logs2" / "mutaciones"; LOG.mkdir(parents=True, exist_ok=True)
NODE = ["fnm", "exec", "--using=20"]
VIEW = "src/csm/workspace/domain/account-metrics-view.ts"
REPO = "src/csm/workspace/infrastructure/adapters/aurora-workspace.repository.ts"
SF = "src/features/csm/utils/metricServerFilters.ts"
SFC = "src/features/csm/components/AccountMetricsServerFilters.tsx"
BE_RUN = [("jest-workspace", BE, NODE + ["npx", "jest", "--ci", "src/csm/workspace"])]
FE_RUN = [("vitest-csm", FE, NODE + ["npx", "vitest", "run", "src/features/csm"])]
OUTSIDE = "const outside = (m: string) => m < windowStart || m > currentMonth;"
DERIVED = "if (from < windowStart || to > currentMonth) {"
M = [
 ("BASE-be", BE, [], BE_RUN),
 ("BASE-fe", FE, [], FE_RUN),
 # --- backend, las cinco que declara el autor en #410 ---
 ("B1-sin-tope-del-periodo", BE, [(VIEW, OUTSIDE, "const outside = (m: string) => m < '0000';"), (VIEW, DERIVED, "if (from < '0000' || to > '9999') {")], BE_RUN),
 ("B2-tope-a-toda-comparacion", BE, [(VIEW, "applied.compare === 'custom' &&", "applied.compare !== undefined &&")], BE_RUN),
 ("B3-default-sin-acotar", BE, [(VIEW, "input.from ?? (defaultFrom < windowStart ? windowStart : defaultFrom);", "input.from ?? defaultFrom;")], BE_RUN),
 ("B4-ventana-35", BE, [(VIEW, "export const READ_WINDOW_MONTHS = 36;", "export const READ_WINDOW_MONTHS = 35;")], BE_RUN),
 ("B5-chargebacks-won-a-other", BE, [(VIEW, "    number_of_chargebacks_won: 'payments_risk',\n", "")], BE_RUN),
 # --- backend, de QA ---
 ("B6-rechaza-el-primer-mes-de-la-ventana", BE, [(VIEW, OUTSIDE, "const outside = (m: string) => m <= windowStart || m > currentMonth;")], BE_RUN),
 ("B7-acepta-meses-futuros", BE, [(VIEW, OUTSIDE, "const outside = (m: string) => m < windowStart || m > '9999-12';"), (VIEW, DERIVED, "if (from < windowStart || to > '9999-12') {")], BE_RUN),
 ("B8-to-por-defecto-sin-acotar-al-mes-actual", BE, [(VIEW, "input.to ?? (newest < currentMonth ? newest : currentMonth);", "input.to ?? newest;")], BE_RUN),
 ("B9-sql-lee-35-meses", BE, [(REPO, "INTERVAL '${READ_WINDOW_MONTHS} months'", "INTERVAL '${READ_WINDOW_MONTHS - 1} months'")], BE_RUN),
 ("B10-400-sin-nombrar-la-ventana", BE, [(VIEW, "`the period must lie within ${window}, the months that can have data (got ${sent})`", "`invalid period (got ${sent})`")], BE_RUN),
 ("B11-comparacion-custom-sin-tope", BE, [(VIEW, "applied.compare === 'custom' &&", "applied.compare === ('never' as string) &&")], BE_RUN),
 # --- frontend, de QA (el autor no declara mutaciones en #216) ---
 ("F1-enlace-sin-acotar", FE, [(SF, "  if (needsBounds && !bounds) return { kind: \"needs-anchor\" };\n  const filters = clampMetricServerFilters(requested, bounds);", "  if (needsBounds && !bounds) return { kind: \"needs-anchor\" };\n  const filters = requested;")], FE_RUN),
 ("F2-no-espera-a-los-limites", FE, [(SF, "  if (needsBounds && !bounds) return { kind: \"needs-anchor\" };\n", "")], FE_RUN),
 ("F3-copia-a-custom-sin-acotar", FE, [(SFC, "? (clampRange(a, bounds) ?? {", "? (a ?? {")], FE_RUN),
 ("F4-inicio-de-comparacion-sin-acotar", FE, [(SF, "const start = clampMonth(next.compareFrom, bounds);", "const start = next.compareFrom;")], FE_RUN),
 ("F5-rango-totalmente-fuera-se-acota", FE, [(SF, "range.to < bounds.from || range.from > bounds.to", "range.to < '0000' && range.from > '9999'")], FE_RUN),
 ("F6-selectores-muestran-lo-pedido", FE, [(SF, "  // The same clamp the query used, so the pickers show the range sent.\n  const filters = clampMetricServerFilters(requested, bounds);", "  const filters = requested;")], FE_RUN),
 ("F7-mes-actual-en-hora-local", FE, [(SF, "fromIndex(today.getUTCFullYear() * 12 + today.getUTCMonth());", "fromIndex(today.getFullYear() * 12 + today.getMonth());")], FE_RUN),
]
only = set(sys.argv[2:])
summary = []
for name, repo, edits, runs in M:
    if only and name not in only: continue
    files = sorted({rel for rel, _, _ in edits})
    orig = {rel: (repo / rel).read_text() for rel in files}
    try:
        for rel, old, new in edits:
            src = (repo / rel).read_text()
            assert src.count(old) == 1, f"{name}: patron encontrado {src.count(old)} veces en {rel}"
            (repo / rel).write_text(src.replace(old, new))
        res = []
        for label, cwd, cmd in runs:
            t0 = time.time()
            p = subprocess.run(cmd, cwd=cwd, env=dict(os.environ, CI="true"), capture_output=True, text=True)
            out = p.stdout + p.stderr
            (LOG / f"{name}__{label}.log").write_text(out)
            clean = re.sub(r"\x1b\[[0-9;]*m", "", out)
            tail = [l.strip() for l in clean.splitlines() if l.strip().startswith(("Tests:", "Tests ", "Test Files", "Test Suites:"))]
            failing = sorted({l.split("›")[0].strip() for l in clean.splitlines() if l.strip().startswith(("●", "FAIL", "×"))})[:4]
            res.append(f"{label}: exit={p.returncode} ({time.time()-t0:.0f}s) {' | '.join(tail[-2:])}\n      primeros fallos: {failing}")
        compile_err = any("0 total" in r for r in res)
        det = any(" exit=0 " not in r for r in res)
        if name.startswith("BASE"):
            verdict = "BASE VERDE" if not det else "BASE ROJA"
        else:
            verdict = "COMPILA MAL (no cuenta)" if compile_err else ("DETECTADA" if det else "NO DETECTADA")
        summary.append(f"{name}: {verdict}\n    " + "\n    ".join(res))
        print(summary[-1], flush=True)
    finally:
        for rel in files:
            subprocess.run(["git", "checkout", "--", rel], cwd=repo, check=True)
            assert (repo / rel).read_text() == orig[rel]
(LOG / ("resumen.txt" if not only else "resumen-parcial.txt")).write_text("\n".join(summary) + "\n")
