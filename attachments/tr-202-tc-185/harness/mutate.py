"""QA TC-185 · reintroducir cada fallo y ver si `npm test` (como el CI) lo detecta.
Todo en un clon temporal; cada fichero se restaura y se verifica por hash."""
import hashlib, subprocess, os, sys
ST = sys.argv[1]
def sha(p): return hashlib.sha256(open(p,'rb').read()).hexdigest()
APP=f"{ST}/server/src/app.ts"; DR=f"{ST}/server/src/routes/surveyDrafts.ts"
RS=f"{ST}/server/src/routes/responses.ts"; DB=f"{ST}/server/src/data/dynamodbStore.ts"
IN=f"{ST}/infra/lib/survey-tool-stateful.stack.ts"
ADMIN = '  app.use("/api/admin", requireAdminAuth);\n'
DRAFTS_ADMIN = '  app.use("/api/admin/survey-drafts", surveyDraftsAdminRouter);\n'
M = [
 ("M1","las rutas de admin de borradores quedan montadas ANTES de la guarda de auth", APP, None, None, "server"),
 ("M2","restore acepta cualquier token", DR, "      || draft.draftTokenHash !== tokenHash\n", "      || false\n", "server"),
 ("M3","un autosave rezagado revive un borrador ya enviado", DR,
   "      && existing.draftTokenHash === draftTokenHash\n    ) {\n      return res.status(409).json({ error: \"Survey draft is no longer active\", code: \"DRAFT_INACTIVE\" });",
   "      && false\n    ) {\n      return res.status(409).json({ error: \"Survey draft is no longer active\", code: \"DRAFT_INACTIVE\" });", "server"),
 ("M4","el mismo resumeRequestId cuenta dos veces", DB,
   "(attribute_not_exists(lastResumeRequestId) OR lastResumeRequestId <> :resumeRequestId)",
   "(attribute_not_exists(lastResumeRequestId) OR lastResumeRequestId <> :resumeRequestId OR lastResumeRequestId = :resumeRequestId)", "server"),
 ("M5","el envio sin token ignora el borrador activo", RS,
   "    } else if (draftClientOrgId && draftRespondentId) {\n", "    } else if (false && draftClientOrgId && draftRespondentId) {\n", "server"),
 ("M6","el indice de admin proyecta las respuestas (comment)", IN,
   "              'entityType',\n", "              'entityType',\n              'comment',\n", "infra"),
]
base = {p: sha(p) for p in (APP,DR,RS,DB,IN)}
def run(where, extra=None):
    cmd = ["npm","test"] if not extra else extra
    r = subprocess.run(cmd, cwd=f"{ST}/{where}", capture_output=True, text=True)
    out = (r.stdout+r.stderr)
    fails = [l.strip() for l in out.splitlines() if l.strip().startswith(("✖","×","FAIL")) or "✗" in l]
    tail = [l for l in out.splitlines() if l.startswith(("ℹ tests","ℹ pass","ℹ fail")) or "Tests " in l]
    return r.returncode, fails, tail
print("MUTACIONES · npm test tal como lo corre el CI")
print("="*78)
for mid, what, path, old, new, where in M:
    src = open(path).read()
    if mid == "M1":
        assert src.count(ADMIN)==1 and src.count(DRAFTS_ADMIN)==1
        mut = src.replace(DRAFTS_ADMIN, "", 1).replace(ADMIN, DRAFTS_ADMIN + ADMIN, 1)
    else:
        c = src.count(old)
        if c != 1: print(f"\n{mid}: ancla aparece {c} veces -> NO APLICADA"); continue
        mut = src.replace(old, new, 1)
    open(path,"w").write(mut)
    code, fails, tail = run(where)
    extra = ""
    if mid == "M1":
        c2, f2, t2 = run("server", ["npx","tsx","--test","src/app.test.ts"])
        extra = f"\n   y si se ejecuta app.test.ts A MANO: {'ROJO' if c2 else 'VERDE'} {' '.join(t2)}"
    open(path,"w").write(src)
    assert sha(path)==base[path], f"{mid}: fichero NO restaurado"
    v = "ROJO (lo detecta)" if code else "VERDE  <-- npm test NO LO DETECTA"
    print(f"\n{mid} — {what}\n   npm test: {v}   {' '.join(tail)}{extra}")
    for f in fails[:3]: print("     ", f[:115])
print("\nTodos los ficheros restaurados e identicos:", all(sha(p)==h for p,h in base.items()))
