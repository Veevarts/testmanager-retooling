#!/usr/bin/env python3
"""Mutaciones del arreglo de IM-1314 ("#219") sobre main. Cada una se aplica, se corren MyDayTasksTab.test.tsx y
SuggestionPoolModal.test.tsx con Node 20 y se restaura con git checkout. Nada se comitea."""
import subprocess, pathlib, re, sys, os
FE = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
TAB = "src/features/csm/components/MyDayTasksTab.tsx"; TOAST = "src/features/csm/components/TaskToastBanner.tsx"
FILES = [TAB, TOAST]
TESTS = ["src/features/csm/components/MyDayTasksTab.test.tsx", "src/features/csm/components/SuggestionPoolModal.test.tsx"]
def rep(old, new, count=1):
    def f(s):
        assert s.count(old) == count, (old[:60], s.count(old)); return s.replace(old, new)
    return f
M = [
 ("BASE", "sin cambios (control)", []),
 ("G1", "closeModal vuelve siempre a la pagina", [(TAB, rep('setModal(isPoolFlowRef.current ? { kind: "pool" } : { kind: "none" });', 'setModal({ kind: "none" });'))]),
 ("G2", "el pool se desmonta cuando lo tapa el detalle", [(TAB, rep("{isPoolFlow ? (\n        <SuggestionPoolModal", '{isPoolFlow && modal.kind === "pool" ? (\n        <SuggestionPoolModal'))]),
 ("G3", "Accept no oculta la fila en el pool", [(TAB, rep("      setHiddenInPool(task.id, true);\n      closeModal();\n      // Not while", "      closeModal();\n      // Not while"))]),
 ("G4", "Undo no devuelve la fila al pool", [(TAB, rep("            setHiddenInPool(task.id, false);\n", ""))]),
 ("G5", "cerrar el pool no vacia las filas ocultas de la visita", [(TAB, rep("    setPoolFlow(false);\n    setPoolHiddenIds(new Set());", "    setPoolFlow(false);"))]),
 ("G6", "una accion resuelta con el pool cerrado siembra la visita siguiente", [(TAB, rep("    if (hidden && !isPoolFlowRef.current) return;\n", ""))]),
 ("G7", "el aviso vuelve debajo de los modales (sin top-layer, z-50)", [(TOAST, rep('    data-react-aria-top-layer="true"\n', "")), (TOAST, rep("z-[60]", "z-50"))]),
]
def run(cmd, **kw): return subprocess.run(cmd, cwd=FE, capture_output=True, text=True, **kw)
summary = []
for key, desc, edits in M:
    run(["git", "checkout", "--", *FILES])
    try:
        for path, fn in edits:
            p = FE / path; p.write_text(fn(p.read_text()))
    except AssertionError as e:
        summary.append((key, desc, f"NO APLICADA {e}", [])); continue
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
