#!/usr/bin/env python3
"""Mutaciones del arreglo de TR-211 N1 (frontend #220). Cada mutacion se aplica sobre main,
se corren los dos ficheros de test del cambio y se restaura con git checkout. Nunca se comitea."""
import subprocess, pathlib, re, sys
FE = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
AD = "src/features/csm/api/playbookEvaluations.ts"
UI = "src/features/csm/components/PlaybookEvaluationList.tsx"
TESTS = ["src/features/csm/api/playbookAdapters.test.ts", "src/features/csm/pages/PlaybookEvaluationsPage.test.tsx"]
ADAPTER = '''      mode:
        row.verdict === "fired"
          ? "active"
          : row.verdict === "shadow_fired"
            ? "shadow"
            : null,'''
RENDER_MODE = '''              {evaluation.mode !== null
                ? `evaluated in ${evaluation.mode === "shadow" ? "shadow mode" : "live mode"}`
                : ""}'''
RENDER_GATE = '''{evaluation.playbookVersion !== null || evaluation.mode !== null ? ('''
M = [
 ("BASE", "sin cambios (control)", []),
 ("M1", "adaptador: vuelve el ternario de #181 (todo lo que no es shadow_fired es live)",
  [(AD, ADAPTER, '      mode: row.verdict === "shadow_fired" ? "shadow" : "active",')]),
 ("M2", "adaptador: adivina 'shadow' para blocked/error",
  [(AD, ADAPTER, ADAPTER.replace(': null,', ': "shadow",'))]),
 ("M3", "adaptador: ninguna fila conoce su modo (null siempre)",
  [(AD, ADAPTER, '      mode: null,')]),
 ("M4", "adaptador: invierte los dos veredictos conocidos",
  [(AD, ADAPTER, ADAPTER.replace('? "active"', '? "__A__"').replace('? "shadow"', '? "active"').replace('"__A__"', '"shadow"'))]),
 ("M5", "render: null pinta 'live mode' (el pie de antes)",
  [(UI, RENDER_MODE, '              {`evaluated in ${evaluation.mode === "shadow" ? "shadow mode" : "live mode"}`}')]),
 ("M6", "render: null pinta 'shadow mode'",
  [(UI, RENDER_MODE, '              {`evaluated in ${evaluation.mode === "active" ? "live mode" : "shadow mode"}`}')]),
 ("M7", "render: se borra la clausula de modo (sobrecorreccion)",
  [(UI, RENDER_MODE, '              {""}')]),
 ("M8", "render: null deja 'evaluated in' colgando sin objeto",
  [(UI, RENDER_MODE, RENDER_MODE.replace(': ""}', ': "evaluated in "}'))]),
]
def run(cmd, **kw): return subprocess.run(cmd, cwd=FE, capture_output=True, text=True, **kw)
summary = []
for key, desc, edits in M:
    run(["git", "checkout", "--", AD, UI])
    ok = True
    for path, old, new in edits:
        p = FE / path; s = p.read_text()
        if s.count(old) != 1: ok = False; print(key, "PATRON NO ENCONTRADO", path); break
        p.write_text(s.replace(old, new))
    if not ok: summary.append((key, desc, "NO APLICADA", "")); continue
    diff = run(["git", "diff", "--", AD, UI]).stdout
    r = run(["fnm", "exec", "--using=20", "npx", "vitest", "run", "--reporter=verbose", *TESTS], env={**__import__("os").environ, "CI": "true"})
    log = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)
    (OUT / f"{key}.log").write_text(f"# {key}: {desc}\n\n## diff\n{diff}\n## vitest\n{log}")
    tl = [l.strip() for l in log.splitlines() if l.strip().startswith("Tests ")]
    failed = [l.strip() for l in log.splitlines() if l.strip().startswith("×") or l.strip().startswith("✗")]
    summary.append((key, desc, f"exit={r.returncode} {tl[-1] if tl else '?'}", "; ".join(failed[:6])))
run(["git", "checkout", "--", AD, UI])
with open(OUT / "resumen.txt", "w") as f:
    for key, desc, res, failed in summary:
        f.write(f"{key} | {desc} | {res}\n")
        if failed: f.write(f"    rojos: {failed}\n")
print((OUT / "resumen.txt").read_text())
print("git status:", run(["git", "status", "--short"]).stdout or "limpio")
