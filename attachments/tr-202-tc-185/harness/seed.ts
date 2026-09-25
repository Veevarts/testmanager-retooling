// Siembra una feature y una encuesta NPS activa de QA con el store REAL del servidor.
import { store } from "../src/data/dynamodbStore.js";
const feature = await store.createFeature({
  name: "QA TC-185 feature", slug: "qa-tc185", description: "QA IM-1302 local", productOwner: null,
  version: null, implementationPerson: null, customerSuccessExecutive: null, isFeature: true,
});
const base = {
  featureId: feature.id, type: "NPS", scale: 10, questionText: "QA TC-185: how likely to recommend?",
  followUpQuestion: "QA TC-185: why?", followUpOptions: null, followUpRequired: false,
  companyRecommendQuestion: "QA TC-185: recommend the company?", companyRecommendRequired: false,
  questionOrder: null, customQuestions: null, layout: null, audience: null, audienceDetails: null,
  triggerType: null, triggerCounter: null, triggerDate: null, triggerDetails: null, active: true,
  scoreReasonEnabled: false, scoreReasonLabel: null, scoreReasonRequired: false, maxImpressions: null,
  maxDismissals: null, isGeneralSurvey: false, generalClientOrgId: null, accountCreatedDelayDays: null,
} as const;
const survey = await store.createSurvey({ ...base } as never, { kind: "none" });
console.log(JSON.stringify({ featureId: feature.id, surveyId: survey.id, active: survey.active }));
