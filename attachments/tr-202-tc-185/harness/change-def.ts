// Cambia SOLO el texto de la pregunta principal de la encuesta indicada (cambio "de errata").
import { store } from "../src/data/dynamodbStore.js";
const id = Number(process.argv[2]); const s = await store.getSurveyById(id) as any;
const expected = { featureId: s.featureId, active: s.active, isGeneralSurvey: s.isGeneralSurvey, audience: s.audience, audienceDetails: s.audienceDetails, generalClientOrgId: s.generalClientOrgId };
await store.updateSurvey(id, { questionText: s.questionText + " (texto corregido)" }, { previous: { kind: "none" }, next: { kind: "none" }, expected } as never);
console.log("definicion cambiada", id);
