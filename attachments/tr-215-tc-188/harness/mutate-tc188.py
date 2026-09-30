#!/usr/bin/env python3
"""Mutaciones del arreglo de IM-1312 ("#218") sobre main (d8a356c, que ya lleva IM-1314).
Cada mutacion se aplica sobre MyDayTasksTab.tsx, se corre la copia del fichero de tests del
componente con los 2 specs de QA anadidos, y se restaura con git checkout. Nunca se comitea."""
import subprocess, pathlib, re, sys, os
FE = pathlib.Path(sys.argv[1]); OUT = pathlib.Path(sys.argv[2]); OUT.mkdir(parents=True, exist_ok=True)
SRC = "src/features/csm/components/MyDayTasksTab.tsx"
TEST = "src/features/csm/components/MyDayTasksTab.qa1312.test.tsx"
HAND = """          onOpenDetail={(task) => {
            setPoolTask(task);
            setModal({ kind: "detail", taskId: task.id });
          }}"""
MAPFIRST = "      ...(poolTask ? [poolTask] : []),\n      ...suggestions.suggestions,"
DELETED = "      ...lists.deleted,\n    ]) {"
CLOSE_MODAL = """    setDrafts({});
    setPoolTask(null);
  }, []);"""
CLOSE_POOL = """    setDrafts({});
    setPoolTask(null);
  }, [setPoolFlow]);"""
M = [
 ("BASE", "sin cambios (control)", []),
 ("M1", "Details del pool no entrega la fila (el arreglo revertido en su punto de entrada)",
  [(HAND, HAND.replace("            setPoolTask(task);\n", ""))]),
 ("M2", "la fila del pool no entra en el mapa por id",
  [(MAPFIRST, "      ...suggestions.suggestions,")]),
 ("M3", "la fila del pool entra AL FINAL del mapa (la copia vieja gana a la fresca)",
  [(MAPFIRST, "      ...suggestions.suggestions,"), (DELETED, "      ...lists.deleted,\n      ...(poolTask ? [poolTask] : []),\n    ]) {")]),
 ("M4", "closeModal no descarta la fila del pool",
  [(CLOSE_MODAL, "    setDrafts({});\n  }, []);")]),
 ("M5", "closePool no descarta la fila del pool",
  [(CLOSE_POOL, "    setDrafts({});\n  }, [setPoolFlow]);")]),
 ("M6", "la primera fila entregada se queda pegada (no se sustituye ni se descarta al cerrar)",
  [(HAND, HAND.replace("setPoolTask(task);", "setPoolTask((current) => current ?? task);")),
   (CLOSE_MODAL, "    setDrafts({});\n  }, []);")]),
 ("M7", "Details del pool entrega la fila pero abre el detalle con el id de la PRIMERA fila entregada",
  [(HAND, HAND.replace('setModal({ kind: "detail", taskId: task.id });', 'setModal({ kind: "detail", taskId: (poolTask ?? task).id });')),
   (CLOSE_MODAL, "    setDrafts({});\n  }, []);")]),
]
def run(cmd, **kw): return subprocess.run(cmd, cwd=FE, capture_output=True, text=True, **kw)
summary = []
for key, desc, edits in M:
    run(["git", "checkout", "--", SRC])
    ok = True
    for old, new in edits:
        p = FE / SRC; s = p.read_text()
        if s.count(old) != 1: ok = False; print(key, "PATRON NO ENCONTRADO:", old[:60]); break
        p.write_text(s.replace(old, new))
    if not ok: summary.append((key, desc, "NO APLICADA", "")); continue
    diff = run(["git", "diff", "--", SRC]).stdout
    r = run(["npx", "vitest", "run", "--reporter=verbose", TEST], env={**os.environ, "CI": "true"})
    log = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)
    (OUT / f"{key}.log").write_text(f"# {key}: {desc}\n\n## diff\n{diff}\n## vitest\n{log}")
    tl = [l.strip() for l in log.splitlines() if l.strip().startswith("Tests ")]
    failed = sorted({re.sub(r" \d+ms$", "", l.strip().split(" > ")[-1]) for l in log.splitlines() if l.strip().startswith("×")})
    summary.append((key, desc, f"exit={r.returncode} {tl[-1] if tl else '?'}", failed))
run(["git", "checkout", "--", SRC])
with open(OUT / "resumen.txt", "w") as f:
    for key, desc, res, failed in summary:
        f.write(f"{key} | {desc} | {res}\n")
        for t in failed: f.write(f"    rojo: {t}\n")
print((OUT / "resumen.txt").read_text())
print("git status:", run(["git", "status", "--short"]).stdout or "limpio")
