#!/usr/bin/env python3
"""TR-217 v2 / TC-190 (IM-1314): mutations of FE #222 (f8c2881) against the pool specs.
Usage: mutate-fe-tc190-v2.py <fe-clone> <out.txt>"""
import os, subprocess, sys, pathlib
fe, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
F = 'src/features/csm/components/SuggestionPoolModal.tsx'
SPECS = ['src/features/csm/components/MyDayTasksTab.test.tsx', 'src/features/csm/components/SuggestionPoolModal.test.tsx']
M = [
  ('R1', 'if (row) body.scrollTop += rowOffsetIn(body, row) - place.rowOffset;', 'if (row) void 0;', 'sin la correccion por fila (solo pixeles)'),
  ('R2', 'if (!restoringRef.current) placeRef.current = placeOf(event.currentTarget);', 'placeRef.current = placeOf(event.currentTarget);', 'guarda los scroll de la propia restauracion'),
  ('R3', 'return (row.getBoundingClientRect().top - box.top) / scale;', 'return row.getBoundingClientRect().top - box.top;', 'desplazamiento sin dividir por la escala del modal'),
  ('R4', 'aria-busy={pool.isLoadingMore}', 'aria-busy={pool.isLoadingMore}\n                isDisabled={pool.isLoadingMore}', 'Load more vuelve a deshabilitarse al cargar'),
  ('R5', '    if (!lost) return;\n', '    return;\n', 'sin mover el foco tras la ultima pagina'),
  ('R6', '.find((task) => !hiddenTaskIds.has(task.id));', '.find(() => true);', 'el foco va a una fila ya atendida'),
  ('R7', 'if (row.getBoundingClientRect().bottom > top) {', 'if (true) {', 'recuerda la primera fila aunque este fuera de la vista'),
]
lines = []
for key, old, new, what in M:
    p = fe / F; src = p.read_text(); n = src.count(old)
    if n != 1:
        lines.append(f'{key}  NO APLICADA ({n})  {what}'); continue
    p.write_text(src.replace(old, new))
    try:
        r = subprocess.run(['fnm', 'exec', '--using=20', 'npx', 'vitest', 'run', *SPECS], cwd=fe, capture_output=True, text=True)
        txt = (r.stdout + r.stderr).replace('\x1b[', '\x1b[')
        import re; txt = re.sub(r'\x1b\[[0-9;]*m', '', txt)
        summ = [l.strip() for l in txt.splitlines() if l.strip().startswith('Tests ')]
        fails = [l.strip() for l in txt.splitlines() if l.strip().startswith('×')][:3]
        lines.append(f'{key}  {"DETECTADA" if r.returncode else "SOBREVIVE":9}  {what}  | {summ[-1] if summ else "?"}')
        lines += [f'      {f[:160]}' for f in fails]
    finally:
        subprocess.run(['git', 'checkout', '--', F], cwd=fe, check=True)
out.write_text('\n'.join(lines) + '\n'); print('\n'.join(lines))
