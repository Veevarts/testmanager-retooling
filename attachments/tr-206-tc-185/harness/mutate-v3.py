"""QA TC-185 v3 · PR #92 · reintroducir cada fallo y ver si `npm test` (como el CI) lo detecta.
Cada fichero se restaura con git checkout y se verifica al final que el arbol queda limpio."""
import subprocess, sys
ST = sys.argv[1]
ADMIN = '  app.use("/api/admin", requireAdminAuth);\n'
DRAFTS_ADMIN = '  app.use("/api/admin/survey-drafts", surveyDraftsAdminRouter);\n'
M = [
 ("M1", "rutas de admin de borradores montadas ANTES de la guarda de auth (TR-202: no detectada)", "server/src/app.ts", "M1", None, "server"),
 ("M4", "el mismo resumeRequestId cuenta dos veces (TR-202: no detectada)", "server/src/data/dynamodbStore.ts",
   "(attribute_not_exists(lastResumeRequestId) OR lastResumeRequestId <> :resumeRequestId)",
   "(attribute_not_exists(lastResumeRequestId) OR lastResumeRequestId <> :resumeRequestId OR lastResumeRequestId = :resumeRequestId)", "server"),
 ("M9", "toma automatica al pulsar Submit (TR-205: no detectada)", "client/src/pages/SurveyRespondPage.tsx",
   "const saved = await api.surveyDrafts.save({ ...payload, draftToken: draftTokenRef.current ?? payload.draftToken });",
   "const saved = await api.surveyDrafts.save({ ...payload, draftToken: draftTokenRef.current ?? payload.draftToken, replaceExistingDraft: true });", "client"),
 ("M11", "el envio del desplazado vuelve a DRAFT_INACTIVE (N1, servidor)", "server/src/routes/responses.ts",
   "        && requestedDraft.status === \"in_progress\"\n        && requestedDraft.expiresAt > Math.floor(Date.now() / 1000)\n      ) {\n        return res.status(409).json({\n          error: \"Saved progress is active in another browser\",",
   "        && requestedDraft.status === \"in_progress\"\n        && false\n      ) {\n        return res.status(409).json({\n          error: \"Saved progress is active in another browser\",", "server"),
 ("M12", "la pagina ignora el conflicto al enviar (N1, pagina)", "client/src/pages/SurveyRespondPage.tsx",
   "        setDraftRevision((revision) => revision + 1);\n        if (isDraftOwnershipConflict(err)) {\n          setDraftNotice(null);\n          setDraftOwnershipConflict(true);",
   "        setDraftRevision((revision) => revision + 1);\n        if (isDraftOwnershipConflict(err)) {\n          return;\n          setDraftOwnershipConflict(true);", "client"),
 ("M13", "el widget ignora el conflicto al enviar (N1, widget)", "client/src/components/SurveyWidget.tsx",
   "        if (e instanceof WidgetHttpError && isDraftOwnershipConflictCode(e.code)) {\n          setDraftNotice(null);\n          setDraftOwnershipConflict(true);",
   "        if (e instanceof WidgetHttpError && isDraftOwnershipConflictCode(e.code)) {\n          return;\n          setDraftOwnershipConflict(true);", "client"),
 ("M14", "Continue here vuelve a mandar el payload viejo (N2, pagina)", "client/src/pages/SurveyRespondPage.tsx",
   "      const latestPayload = {\n        ...payload,\n        ...buildSurveyDraftAnswerPayload({",
   "      const latestPayload = {\n        ...payload,\n        ...({} as never) && buildSurveyDraftAnswerPayload({", "client"),
]
def run(where):
    r = subprocess.run(["npm", "test"], cwd=f"{ST}/{where}", capture_output=True, text=True, env={**__import__("os").environ, "AWS_ENDPOINT_URL_DYNAMODB": ""})
    out = r.stdout + r.stderr
    fails = [l.strip() for l in out.splitlines() if l.strip().startswith("✖")]
    tail = [l for l in out.splitlines() if l.startswith(("ℹ pass", "ℹ fail"))]
    return r.returncode, fails, tail
print("MUTACIONES v3 · PR #92 (5656962f) · npm test tal como lo corre el CI\n" + "=" * 78)
for mid, what, rel, old, new, where in M:
    p = f"{ST}/{rel}"; src = open(p).read()
    if old == "M1":
        assert src.count(ADMIN) == 1 and src.count(DRAFTS_ADMIN) == 1
        mut = src.replace(DRAFTS_ADMIN, "", 1).replace(ADMIN, DRAFTS_ADMIN + ADMIN, 1)
    else:
        c = src.count(old)
        if c != 1: print(f"\n{mid}: ancla aparece {c} veces -> NO APLICADA"); continue
        mut = src.replace(old, new, 1)
    open(p, "w").write(mut)
    code, fails, tail = run(where)
    subprocess.run(["git", "checkout", "-q", "--", rel], cwd=ST, check=True)
    v = "ROJO (lo detecta)" if code else "VERDE  <-- npm test NO LO DETECTA"
    print(f"\n{mid} — {what}\n   npm test ({where}): {v}   {' '.join(tail)}")
    for f in fails[:3]: print("     ", f[:115])
st = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ST, capture_output=True, text=True).stdout.strip()
print("\nArbol restaurado y limpio:", st == "")
