// Crea (idempotente) la feature y la encuesta QA del escenario 12 en Survey Tool DEV.
import { connect, findPage, adminApi } from "./lib.mjs";
import { writeFileSync } from "node:fs";
const ORG = "00DRt00000WkwJ0MAJ"; // nps_03 (scratch Auctifera asignada a Survey Tool)
const { ctx } = await connect();
const page = findPage(ctx, /surveytool\.dev\.veevart\.ai/);
const fl = (await adminApi(page, "GET", "/api/admin/features")).data;
let feature = fl.find((f) => f.slug === "qa-tc-185-iframe");
if (!feature) {
  const r = await adminApi(page, "POST", "/api/admin/features", { name: "QA TC-185 Iframe", slug: "qa-tc-185-iframe",
    description: "QA IM-1302 TC-185 escenario 12: borrador en el iframe de Salesforce (nps_03)", isFeature: true });
  console.log("feature POST", r.status); feature = r.data;
}
const sl = (await adminApi(page, "GET", `/api/admin/surveys/by-feature/${feature.id}`)).data ?? [];
let survey = (Array.isArray(sl) ? sl : []).find((s) => /QA TC-185 iframe/.test(s.questionText));
if (!survey) {
  const r = await adminApi(page, "POST", "/api/admin/surveys", {
    featureId: feature.id, type: "nps", scale: 10, layout: "single", active: true,
    questionText: "QA TC-185 iframe: how likely are you to recommend Veevart?",
    followUpQuestion: "QA TC-185 iframe: what is the main reason for your score?",
    companyRecommendQuestion: "QA TC-185 iframe: would you recommend the company?",
    audience: "organization", audienceDetails: ORG, isGeneralSurvey: false });
  console.log("survey POST", r.status, r.status >= 400 ? JSON.stringify(r.data) : ""); survey = r.data;
}
const out = { featureId: feature.id, slug: feature.slug, surveyId: survey.id, active: survey.active, audience: survey.audience, audienceDetails: survey.audienceDetails, type: survey.type };
writeFileSync("out/setup.json", JSON.stringify(out, null, 2));
console.log(JSON.stringify(out));
process.exit(0);
