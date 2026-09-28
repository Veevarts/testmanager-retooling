// Solo lectura: borradores de la encuesta 27 y metricas de la feature 16. Uso: node probe.mjs <etiqueta>
import { connect, findPage, adminApi } from "./lib.mjs";
import { appendFileSync } from "node:fs";
const { ctx } = await connect();
const page = findPage(ctx, /surveytool\.dev\.veevart\.ai/);
const drafts = await adminApi(page, "GET", "/api/admin/survey-drafts?surveyId=27");
const list = Array.isArray(drafts.data) ? drafts.data : drafts.data?.items ?? drafts.data?.drafts ?? [];
const mine = list.filter((d) => String(d.surveyId) === "27");
const feat = await adminApi(page, "GET", "/api/admin/analytics/features/16");
const resp = await adminApi(page, "GET", "/api/admin/responses?featureId=16");
const rl = Array.isArray(resp.data) ? resp.data : resp.data?.items ?? resp.data?.responses ?? [];
const r27 = rl.filter((r) => String(r.surveyId) === "27");
let detail = null;
if (mine[0]) {
  const d = mine[0];
  const det = await adminApi(page, "GET", `/api/admin/survey-drafts/27/${encodeURIComponent(d.clientOrgId)}/${encodeURIComponent(d.respondentId)}`);
  const a = det.data?.answers ?? det.data?.draft?.answers ?? det.data;
  detail = { status: det.status, keys: Object.keys(det.data ?? {}), score: a?.score, comment: a?.comment, companyRecommendScore: a?.companyRecommendScore };
}
const rec = { label: process.argv[2], at: new Date().toISOString(), draftsStatus: drafts.status,
  drafts: mine.map((d) => ({ status: d.status, clientOrgId: d.clientOrgId, respondentId: d.respondentId, answeredCount: d.answeredQuestionCount ?? d.answeredCount, total: d.totalQuestionCount, currentStep: d.currentStep, resumeCount: d.resumeCount, saveSequence: d.saveSequence, startedAt: d.startedAt, lastSavedAt: d.lastSavedAt })),
  detail, analyticsStatus: feat.status, analytics: feat.data && JSON.stringify(feat.data).slice(0, 600), responses27: r27.map((r) => ({ score: r.score, comment: r.comment, companyRecommendScore: r.companyRecommendScore, clientOrgId: r.clientOrgId, salesforceOrgId: r.salesforceOrgId, respondentId: r.respondentId })) , responsesStatus: resp.status };
appendFileSync("out/probes.jsonl", JSON.stringify(rec) + "\n");
console.log(JSON.stringify(rec, null, 1).replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g, "<correo>"));
process.exit(0);
