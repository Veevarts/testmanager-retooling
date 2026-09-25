// Feature de UI con UNA sola encuesta nps activa de tres preguntas (principal, por que, empresa).
import { store } from "../src/data/dynamodbStore.js";
const f = await store.createFeature({ name: "QA TC-185 UI", slug: "qa-tc185-ui", description: "QA IM-1302 UI local",
  productOwner: null, version: null, implementationPerson: null, customerSuccessExecutive: null, isFeature: true });
const s1 = await store.getSurveyById(1) as any;
const s = await store.createSurvey({ ...s1, id: undefined, createdAt: undefined, featureId: f.id, type: "nps",
  questionText: "QA TC-185 UI: how likely are you to recommend us?", followUpQuestion: "QA TC-185 UI: what is the main reason?",
  companyRecommendQuestion: "QA TC-185 UI: would you recommend the company?" } as never, { kind: "none" });
console.log(JSON.stringify({ featureId: f.id, slug: f.slug, surveyId: s.id, type: s.type }));
