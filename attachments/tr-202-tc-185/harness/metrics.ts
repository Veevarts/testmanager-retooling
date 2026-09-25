// AC8 · las metricas no se mueven con un borrador y se mueven UNA vez con el envio.
import { randomBytes } from "node:crypto";
import { store } from "../src/data/dynamodbStore.js";
import { createSessionCookie } from "../src/lib/auth.js";
const cookie = createSessionCookie({ sub: "qa-tc185-admin" }).split(";")[0];
const s1 = await store.getSurveyById(1);
const s = await store.createSurvey({ ...(s1 as any), id: undefined, createdAt: undefined, type: "nps", questionText: "QA TC-185 nps metricas" } as never, { kind: "none" });
const q = "?from=2026-01-01&to=2026-12-31";
const summary = async () => {
  const r = await fetch("http://localhost:4599/api/admin/analytics/summary" + q, { headers: { cookie } });
  const row = (await r.json()).find((x: any) => x.surveyId === s.id);
  return row ? { type: row.type, total: row.total, nps: row.nps ?? row.score ?? null, promoters: row.promotersPct ?? row.promoterPct ?? null } : { total: 0 };
};
const post = (p: string, b: unknown) => fetch("http://localhost:4599" + p, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(b) }).then((r) => r.status);
const t = randomBytes(32).toString("base64url");
const ctx = { surveyId: s.id, featureId: 1, clientOrgId: "qa-org-tc185", respondentId: "qa-tc185-r10" };
console.log("0 · antes de nada          ", JSON.stringify(await summary()));
console.log("1 · crear borrador (score 10)", await post("/api/survey-drafts", { ...ctx, draftToken: t, score: 10, currentPage: 0, saveSequence: 1 }));
console.log("  · con solo el borrador   ", JSON.stringify(await summary()));
console.log("2 · enviar                  ", await post("/api/responses", { ...ctx, score: 10, draftToken: t }));
console.log("  · tras el envio          ", JSON.stringify(await summary()));
