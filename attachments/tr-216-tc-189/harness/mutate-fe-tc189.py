#!/usr/bin/env python3
"""Mutaciones del frontend de IM-1313 ("#217") sobre main. Cada una se aplica, se corren los 5 ficheros de
tests del PR y se restaura con git checkout. Nada se comitea."""
import subprocess, pathlib, re, sys, os
FE = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
API = "src/features/csm/api/tasks.ts"; HK = "src/features/csm/hooks/useSuggestionPool.ts"; PN = "src/features/csm/components/MyDaySuggestedPanel.tsx"
FILES = [API, HK, PN]
TESTS = ["src/features/csm/api/tasks.test.ts", "src/features/csm/components/MyDaySuggestedPanel.onImplementation.test.tsx",
         "src/features/csm/components/SuggestionPoolModal.onImplementation.test.tsx", "src/features/csm/hooks/useSuggestionPool.test.tsx",
         "src/features/csm/schemas/tasks.test.ts"]
def rep(old, new):
    def f(s):
        assert s.count(old) == 1, (old[:60], s.count(old)); return s.replace(old, new)
    return f
M = [
 ("BASE", "sin cambios (control)", []),
 ("F1", "la API nunca envia includeOnImplementation", [(API, rep("if (options.includeOnImplementation === true) {", "if (false) {"))]),
 ("F2", "cambiar el filtro no descarta el cursor (no vuelve a la pagina 1)", [(HK, rep("      setInclude(include);\n      cursorRef.current = null;", "      setInclude(include);"))]),
 ("F3", "Load more pagina siempre el conjunto filtrado aunque este revelado", [(HK, rep("void fetchPage(cursorRef.current, false, includeRef.current);", "void fetchPage(cursorRef.current, false, false);"))]),
 ("F4", "el contador de ocultas se ignora (siempre 0)", [(HK, rep("if (!include) setHidden(page.hiddenOnImplementation ?? 0);", "if (!include) setHidden(0);"))]),
 ("F5", "el chip On implementation no se pinta", [(PN, rep("{task.accountOnImplementation === true ? (", "{false ? ("))]),
]
def run(cmd, **kw): return subprocess.run(cmd, cwd=FE, capture_output=True, text=True, **kw)
summary = []
for key, desc, edits in M:
    run(["git", "checkout", "--", *FILES])
    for path, fn in edits:
        p = FE / path; p.write_text(fn(p.read_text()))
    diff = run(["git", "diff", "--", *FILES]).stdout
    r = run(["fnm", "exec", "--using=20", "npx", "vitest", "run", "--reporter=verbose", *TESTS], env={**os.environ, "CI": "true"})
    log = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)
    (OUT / f"{key}.log").write_text(f"# {key}: {desc}\n\n## diff\n{diff}\n## vitest\n{log[-8000:]}")
    tl = [l.strip() for l in log.splitlines() if l.strip().startswith("Tests ")]
    failed = sorted({re.sub(r" \d+ms$", "", l.strip().split(" > ")[-1]) for l in log.splitlines() if l.strip().startswith("×")})
    summary.append((key, desc, tl[-1] if tl else "?", failed))
run(["git", "checkout", "--", *FILES])
with open(OUT / "resumen.txt", "w") as f:
    for key, desc, res, failed in summary:
        f.write(f"{key} | {desc} | {res}\n")
        for t in failed[:6]: f.write(f"    rojo: {t}\n")
        if len(failed) > 6: f.write(f"    ... y {len(failed) - 6} mas\n")
print((OUT / "resumen.txt").read_text()); print("git status:", run(["git", "status", "--short"]).stdout or "limpio")
