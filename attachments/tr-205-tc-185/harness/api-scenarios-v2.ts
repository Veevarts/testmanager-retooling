/**
 * QA TC-185 · IM-1302 — v2 (PR #91, merge 3789cb5c) — escenarios de API contra el servidor REAL (src/index.ts) y
 * DynamoDB REAL (DynamoDB Local, tablas identicas al stack sintetizado).
 * Nada es un doble: HTTP -> rutas -> store -> motor de DynamoDB con sus condiciones y
 * transacciones. Encuestados sinteticos qa-tc185-*; ningun dato personal.
 */
import { randomBytes, createHash } from "node:crypto";
import { writeFileSync, mkdirSync } from "node:fs";
import { DynamoDBClient, ScanCommand, DescribeTableCommand, QueryCommand, UpdateItemCommand } from "@aws-sdk/client-dynamodb";
import { unmarshall } from "@aws-sdk/util-dynamodb";
import { store, getSurveyToolTableNames } from "../src/data/dynamodbStore.js";
import { createSessionCookie } from "../src/lib/auth.js";

const BASE = "http://localhost:4599";
const OUT = process.argv[2];
const T = getSurveyToolTableNames();
const ddb = new DynamoDBClient({});
const tok = () => randomBytes(32).toString("base64url");
const hash = (t: string) => createHash("sha256").update(t).digest("hex");
const ORG = "qa-org-tc185";
const log: Record<string, unknown[]> = {};
function rec(s: string, step: string, data: unknown) { (log[s] ??= []).push({ step, ...(data as object) }); }

async function call(method: string, path: string, body?: unknown, cookie?: string) {
  const r = await fetch(BASE + path, {
    method, headers: { "content-type": "application/json", ...(cookie ? { cookie } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text(); let json: any = null; try { json = JSON.parse(text); } catch {}
  return { status: r.status, body: json ?? text.slice(0, 300) };
}
const draft = (surveyId: number, respondentId: string, extra: Record<string, unknown>) =>
  ({ surveyId, featureId: 1, clientOrgId: ORG, respondentId, currentPage: 0, ...extra });
async function rawItems(table: string) {
  const out: any[] = []; let k: any;
  do { const r = await ddb.send(new ScanCommand({ TableName: table, ExclusiveStartKey: k })); out.push(...(r.Items ?? []).map((i) => unmarshall(i))); k = r.LastEvaluatedKey; } while (k);
  return out;
}
const draftsOf = async (respondentId: string) => (await rawItems(T.respondentState)).filter((i) => i.entityType === "surveyDraft" && i.respondentId === respondentId);
const responsesOf = async (respondentId: string) => (await store.listResponses({})).filter((r: any) => r.respondentId === respondentId);
const pickDraft = (d: any) => d && ({ status: d.status, saveSequence: d.saveSequence, currentPage: d.currentPage,
  answered: d.answeredQuestionCount, total: d.totalQuestionCount, resumeCount: d.resumeCount,
  hasScore: d.score != null, hasComment: d.comment != null, responseId: d.responseId ?? null });

// ---------- AC1 · un borrador, actualizado en su sitio ----------
{
  const S = "AC1"; const t1 = tok();
  let r = await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r1", { draftToken: t1, score: 9, saveSequence: 1 }));
  rec(S, "crear con la primera respuesta", { status: r.status, devuelveToken: typeof r.body?.draftToken === "string" });
  r = await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r1", { draftToken: t1, score: 9, comment: "qa parcial", currentPage: 1, saveSequence: 2 }));
  rec(S, "cambio 1 (seq 2)", { status: r.status });
  r = await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r1", { draftToken: t1, score: 9, comment: "qa parcial", currentPage: 1, saveSequence: 2 }));
  rec(S, "reintento identico (seq 2)", { status: r.status });
  r = await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r1", { draftToken: t1, score: 3, saveSequence: 1 }));
  rec(S, "secuencia antigua (seq 1)", { status: r.status, body: r.body });
  const ds = await draftsOf("qa-tc185-r1");
  rec(S, "estado en DynamoDB", { borradores: ds.length, borrador: pickDraft(ds[0]), respuestas: (await responsesOf("qa-tc185-r1")).length });
  (globalThis as any).t1 = t1;
}

// ---------- AC3 · restore, y el resume contado una vez ----------
{
  const S = "AC3"; const t1 = (globalThis as any).t1;
  const rq = "qa-tc185-resume-000001";
  let r = await call("POST", "/api/survey-drafts/restore", draft(1, "qa-tc185-r1", { draftToken: t1, resumeRequestId: rq }));
  rec(S, "restore", { status: r.status, score: r.body?.score ?? r.body?.draft?.score, comment: r.body?.comment ?? r.body?.draft?.comment, currentPage: r.body?.currentPage ?? r.body?.draft?.currentPage, resumeCount: r.body?.resumeCount ?? r.body?.draft?.resumeCount, claves: Object.keys(r.body ?? {}) });
  r = await call("POST", "/api/survey-drafts/restore", draft(1, "qa-tc185-r1", { draftToken: t1, resumeRequestId: rq }));
  rec(S, "reintento con el mismo resumeRequestId", { status: r.status });
  r = await call("POST", "/api/survey-drafts/restore", draft(1, "qa-tc185-r1", { draftToken: t1, resumeRequestId: "qa-tc185-resume-000002" }));
  rec(S, "restore nuevo (otro resumeRequestId)", { status: r.status });
  const d = (await draftsOf("qa-tc185-r1"))[0];
  rec(S, "estado en DynamoDB", { resumeCount: d?.resumeCount, lastResumedAt: d?.lastResumedAt ?? null });
}

// ---------- AC9 · sin el token no se lee ni se cambia ----------
{
  const S = "AC9"; const before = pickDraft((await draftsOf("qa-tc185-r1"))[0]);
  let r = await call("POST", "/api/survey-drafts/restore", draft(1, "qa-tc185-r1", {}));
  rec(S, "restore SIN token", { status: r.status, filtraRespuestas: JSON.stringify(r.body).includes("qa parcial") });
  r = await call("POST", "/api/survey-drafts/restore", draft(1, "qa-tc185-r1", { draftToken: tok() }));
  rec(S, "restore con token inventado", { status: r.status, code: r.body?.code, filtraRespuestas: JSON.stringify(r.body).includes("qa parcial") });
  r = await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r1", { draftToken: tok(), score: 0, comment: "sobrescrito", saveSequence: 99 }));
  rec(S, "guardar encima con token ajeno", { status: r.status, code: r.body?.code });
  const after = pickDraft((await draftsOf("qa-tc185-r1"))[0]);
  rec(S, "el borrador no cambio", { identico: JSON.stringify(before) === JSON.stringify(after) });
  const item = (await draftsOf("qa-tc185-r1"))[0];
  const flat = JSON.stringify(item);
  rec(S, "que guarda la tabla del token", { guardaHash: item?.draftTokenHash === hash((globalThis as any).t1), contieneTokenEnClaro: flat.includes((globalThis as any).t1) });
}

// ---------- AC5 · enviar, autosave rezagado, reintento ----------
{
  const S = "AC5"; const t3 = tok();
  await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r3", { draftToken: t3, score: 8, comment: "qa r3", saveSequence: 1 }));
  let r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 8, comment: "qa r3", clientOrgId: ORG, respondentId: "qa-tc185-r3", draftToken: t3 });
  const rid = r.body?.id; rec(S, "enviar con token", { status: r.status, responseId: rid });
  r = await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r3", { draftToken: t3, score: 1, saveSequence: 2 }));
  rec(S, "autosave rezagado", { status: r.status, code: r.body?.code });
  r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 8, comment: "qa r3", clientOrgId: ORG, respondentId: "qa-tc185-r3", draftToken: t3 });
  rec(S, "reintento del envio", { status: r.status, mismaRespuesta: r.body?.id === rid });
  const d = (await draftsOf("qa-tc185-r3"))[0];
  rec(S, "estado final", { respuestas: (await responsesOf("qa-tc185-r3")).length, borrador: pickDraft(d) });
}

// ---------- AC6 · cliente antiguo sin token ----------
{
  const S = "AC6";
  let r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 7, clientOrgId: ORG, respondentId: "qa-tc185-r4" });
  rec(S, "sin token y SIN borrador activo", { status: r.status });
  await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r5", { draftToken: tok(), score: 6, saveSequence: 1 }));
  r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 6, clientOrgId: ORG, respondentId: "qa-tc185-r5" });
  rec(S, "sin token y CON borrador activo", { status: r.status, body: r.body, respuestasCreadas: (await responsesOf("qa-tc185-r5")).length });
}

// ---------- F · el mismo encuestado en un SEGUNDO navegador (contrato del fix, PR #91) ----------
{
  const S = "SEGUNDO_NAVEGADOR"; const tA = tok(); const tB = tok(); const R = "qa-tc185-r6";
  let r = await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tA, score: 5, comment: "respuesta de A", saveSequence: 1 }));
  rec(S, "1 navegador A empieza", { status: r.status });
  r = await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tB, score: 10, saveSequence: 1 }));
  rec(S, "2 navegador B autosave con su token (sin replace)", { status: r.status, code: r.body?.code, error: r.body?.error });
  rec(S, "2b el borrador sigue siendo el de A", { borrador: pickDraft((await draftsOf(R))[0]), hashEsA: (await draftsOf(R))[0]?.draftTokenHash === hash(tA) });
  r = await call("POST", "/api/survey-drafts/restore", draft(1, R, { draftToken: tB }));
  rec(S, "3 navegador B restore", { status: r.status, code: r.body?.code, filtraRespuestasDeA: JSON.stringify(r.body).includes("respuesta de A") || r.body?.score === 5, claves: Object.keys(r.body ?? {}) });
  r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 10, clientOrgId: ORG, respondentId: R, draftToken: tB });
  rec(S, "4 navegador B envia con SU token SIN tomar la propiedad", { status: r.status, code: r.body?.code });
  r = await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tB, replaceExistingDraft: true, score: 10, comment: "respuesta de B", saveSequence: 1 }));
  rec(S, "5 navegador B pulsa Continue here (replaceExistingDraft)", { status: r.status, filtraRespuestasDeA: JSON.stringify(r.body).includes("respuesta de A") });
  let d = (await draftsOf(R))[0];
  rec(S, "5b estado tras la toma", { borradores: (await draftsOf(R)).length, borrador: pickDraft(d), hashEsB: d?.draftTokenHash === hash(tB), comentario: d?.comment });
  r = await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tA, score: 4, comment: "A sobrescribe", saveSequence: 2 }));
  rec(S, "6 navegador A (desplazado) autosave", { status: r.status, code: r.body?.code });
  rec(S, "6b A no sobrescribio", { comentario: (await draftsOf(R))[0]?.comment });
  r = await call("POST", "/api/survey-drafts/restore", draft(1, R, { draftToken: tA }));
  rec(S, "7 navegador A restore", { status: r.status, code: r.body?.code, filtraRespuestasDeB: JSON.stringify(r.body).includes("respuesta de B") });
  r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 5, comment: "respuesta de A", clientOrgId: ORG, respondentId: R, draftToken: tA });
  rec(S, "8 navegador A ENVIA con su token viejo (todo guardado, sin cambios pendientes)", { status: r.status, code: r.body?.code, error: r.body?.error });
  r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 10, comment: "respuesta de B", clientOrgId: ORG, respondentId: R, draftToken: tB });
  rec(S, "9 navegador B envia", { status: r.status });
  d = (await draftsOf(R))[0];
  rec(S, "9b final", { respuestas: (await responsesOf(R)).length, comentarioDeLaRespuesta: (await responsesOf(R))[0]?.comment, borrador: pickDraft(d) });
}

// ---------- AC6 literal · cliente sin token cuando hay borrador activo (responses.ts no cambio) ----------
{
  const S = "AC6_CON_BORRADOR";
  const R = "qa-tc185-r7";
  await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tok(), score: 6, saveSequence: 1 }));
  const r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 6, clientOrgId: ORG, respondentId: R });
  rec(S, "envio sin token con borrador activo", { status: r.status, body: r.body, respuestas: (await responsesOf(R)).length });
}

// ---------- AC9 bajo el contrato nuevo · un tercero sin token ----------
{
  const S = "AC9_TERCERO"; const tV = tok(); const R = "qa-tc185-r11";
  await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tV, score: 9, comment: "respuesta de la victima", saveSequence: 1 }));
  let r = await call("POST", "/api/survey-drafts/restore", draft(1, R, { draftToken: tok() }));
  rec(S, "restore con token inventado sobre un borrador ACTIVO", { status: r.status, code: r.body?.code, filtra: JSON.stringify(r.body).includes("victima") });
  r = await call("POST", "/api/survey-drafts/restore", draft(1, "qa-tc185-nadie", { draftToken: tok() }));
  rec(S, "restore con token inventado para un encuestado SIN borrador", { status: r.status, code: r.body?.code });
  const tX = tok();
  r = await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tX, replaceExistingDraft: true, score: 0, comment: "sobrescrito por un tercero", saveSequence: 1 }));
  rec(S, "un tercero sin el token envia replaceExistingDraft", { status: r.status, filtra: JSON.stringify(r.body).includes("victima") });
  const d = (await draftsOf(R))[0];
  rec(S, "que queda guardado", { comentario: d?.comment, score: d?.score, hashEsDelTercero: d?.draftTokenHash === hash(tX) });
  r = await call("POST", "/api/responses", { surveyId: 1, featureId: 1, score: 0, comment: "sobrescrito por un tercero", clientOrgId: ORG, respondentId: R, draftToken: tX });
  rec(S, "el tercero envia una respuesta a nombre del encuestado", { status: r.status, respuestas: (await responsesOf(R)).length });
}

// ---------- Concurrencia · dos navegadores pulsan Continue here a la vez (x20) ----------
{
  const S = "CONCURRENCIA"; const res: Record<string, number> = {}; let ganadorCoincide = 0; let noSobrescrito = 0;
  for (let i = 0; i < 20; i++) {
    const R = `qa-tc185-race-${i}`; const tA = tok(); const tB = tok(); const tC = tok();
    await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tA, score: 1, saveSequence: 1 }));
    const [b, c] = await Promise.all([
      call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tB, replaceExistingDraft: true, score: 2, comment: "B", saveSequence: 1 })),
      call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tC, replaceExistingDraft: true, score: 3, comment: "C", saveSequence: 1 })),
    ]);
    const key = [b.status, c.status].sort().join("+"); res[key] = (res[key] ?? 0) + 1;
    const d = (await draftsOf(R))[0];
    const winner = b.status === 201 ? tB : c.status === 201 ? tC : null;
    if (winner && d?.draftTokenHash === hash(winner)) ganadorCoincide++;
    if (winner && d?.comment === (winner === tB ? "B" : "C")) noSobrescrito++;
  }
  rec(S, "Continue here simultaneo en B y C", { combinaciones: res, ganadorEsElDuenoFinal: ganadorCoincide, respuestasDelGanador: noSobrescrito, de: 20 });
  const res2: Record<string, number> = {}; let dueno: Record<string, number> = {};
  for (let i = 0; i < 20; i++) {
    const R = `qa-tc185-race2-${i}`; const tA = tok(); const tB = tok();
    await call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tA, score: 1, saveSequence: 1 }));
    const [a, b] = await Promise.all([
      call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tA, score: 4, comment: "A", saveSequence: 2 })),
      call("POST", "/api/survey-drafts", draft(1, R, { draftToken: tB, replaceExistingDraft: true, score: 2, comment: "B", saveSequence: 1 })),
    ]);
    const key = `A${a.status}/B${b.status}`; res2[key] = (res2[key] ?? 0) + 1;
    const d = (await draftsOf(R))[0];
    const k2 = d?.draftTokenHash === hash(tB) ? `dueno B, comentario ${d?.comment}` : `dueno A, comentario ${d?.comment}`; dueno[k2] = (dueno[k2] ?? 0) + 1;
  }
  rec(S, "autosave de A y Continue here de B a la vez", { combinaciones: res2, estadoFinal: dueno, de: 20 });
}

// ---------- AC4 · definicion cambiada ----------
{
  const S = "AC4";
  const s1 = await store.getSurveyById(1);
  const s2 = await store.createSurvey({ ...(s1 as any), id: undefined, createdAt: undefined, questionText: "QA TC-185 encuesta 2" } as never, { kind: "none" });
  const t2 = tok(); const t2b = tok();
  await call("POST", "/api/survey-drafts", draft(s2.id, "qa-tc185-r2", { draftToken: t2, score: 4, saveSequence: 1 }));
  await call("POST", "/api/survey-drafts", draft(s2.id, "qa-tc185-r2b", { draftToken: t2b, score: 4, saveSequence: 1 }));
  const expected = { featureId: s2.featureId, active: s2.active, isGeneralSurvey: s2.isGeneralSurvey, audience: s2.audience, audienceDetails: s2.audienceDetails, generalClientOrgId: s2.generalClientOrgId };
  await store.updateSurvey(s2.id, { questionText: "QA TC-185 encuesta 2 (texto corregido)" }, { previous: { kind: "none" }, next: { kind: "none" }, expected } as never);
  let r = await call("POST", "/api/survey-drafts/restore", draft(s2.id, "qa-tc185-r2", { draftToken: t2 }));
  rec(S, "restore tras cambiar SOLO el texto de la pregunta", { status: r.status, code: r.body?.code, cargaRespuestas: r.body?.score != null });
  r = await call("POST", "/api/responses", { surveyId: s2.id, featureId: 1, score: 4, clientOrgId: ORG, respondentId: "qa-tc185-r2b", draftToken: t2b });
  rec(S, "envio con el token de la definicion anterior", { status: r.status, code: r.body?.code });
}

// ---------- AC7/AC8 · rutas de admin ----------
{
  const S = "AC7_AC8";
  let r = await call("GET", "/api/admin/survey-drafts");
  rec(S, "lista SIN sesion", { status: r.status });
  r = await call("GET", "/api/admin/survey-drafts/1/" + ORG + "/qa-tc185-r1");
  rec(S, "detalle SIN sesion", { status: r.status });
  const cookie = createSessionCookie({ sub: "qa-tc185-admin", email: "qa-tc185@example.invalid" }).split(";")[0];
  r = await call("GET", "/api/admin/survey-drafts", undefined, cookie);
  const items = Array.isArray(r.body) ? r.body : (r.body?.items ?? r.body?.drafts ?? []);
  rec(S, "lista CON sesion", { status: r.status, filas: items.length,
    encuestados: items.map((i: any) => i.respondentId).sort(),
    columnas: items[0] ? Object.keys(items[0]).sort() : [],
    llevaRespuestas: JSON.stringify(items).includes("qa parcial"), llevaHash: JSON.stringify(items).includes("draftTokenHash") });
  r = await call("GET", "/api/admin/survey-drafts/1/" + ORG + "/qa-tc185-r1", undefined, cookie);
  rec(S, "detalle CON sesion", { status: r.status, claves: Object.keys(r.body ?? {}).sort(), preguntas: r.body?.questions ?? r.body?.answers ?? null });
  r = await call("GET", "/api/admin/responses", undefined, cookie);
  const resp = Array.isArray(r.body) ? r.body : (r.body?.items ?? r.body?.responses ?? []);
  rec(S, "Responses (admin)", { status: r.status, encuestados: resp.map((x: any) => x.respondentId).sort() });
  r = await call("GET", "/api/admin/responses/export.csv", undefined, cookie);
  const csv = typeof r.body === "string" ? r.body : JSON.stringify(r.body);
  rec(S, "CSV estandar", { status: r.status, contieneR1: csv.includes("qa-tc185-r1"), contieneR3: csv.includes("qa-tc185-r3") });
}

// ---------- AC10 · el indice solo lleva metadatos ----------
{
  const S = "AC10";
  const d = await ddb.send(new DescribeTableCommand({ TableName: T.respondentState }));
  const g = d.Table?.GlobalSecondaryIndexes?.find((x) => x.IndexName === "GSI2");
  rec(S, "proyeccion de GSI2", { tipo: g?.Projection?.ProjectionType, atributos: g?.Projection?.NonKeyAttributes });
  const keys = new Set<string>();
  for (let shard = 0; shard < 16; shard++) {
    const q = await ddb.send(new QueryCommand({ TableName: T.respondentState, IndexName: "GSI2", KeyConditionExpression: "GSI2PK = :p", ExpressionAttributeValues: { ":p": { S: `SURVEY_DRAFT#SHARD#${shard}` } } }));
    for (const it of q.Items ?? []) Object.keys(it).forEach((k) => keys.add(k));
  }
  rec(S, "atributos que devuelve una consulta al indice", { atributos: [...keys].sort(),
    llevaRespuestas: [...keys].some((k) => ["score", "comment", "scoreReason", "customAnswers", "companyRecommendScore"].includes(k)),
    llevaToken: [...keys].some((k) => /token/i.test(k)) });
}

// ---------- Borde · identidad incompleta y caducado ----------
{
  const S = "BORDE";
  let r = await call("POST", "/api/survey-drafts", { surveyId: 1, featureId: 1, respondentId: "qa-tc185-r8", currentPage: 0, saveSequence: 1, draftToken: tok(), score: 5 });
  rec(S, "sin organizacion", { status: r.status, body: r.body });
  r = await call("POST", "/api/survey-drafts", { surveyId: 1, featureId: 1, clientOrgId: ORG, currentPage: 0, saveSequence: 1, draftToken: tok(), score: 5 });
  rec(S, "sin encuestado", { status: r.status });
  const t9 = tok();
  await call("POST", "/api/survey-drafts", draft(1, "qa-tc185-r9", { draftToken: t9, score: 5, saveSequence: 1 }));
  const it = (await draftsOf("qa-tc185-r9"))[0];
  await ddb.send(new UpdateItemCommand({ TableName: T.respondentState, Key: { PK: { S: it.PK }, SK: { S: it.SK } }, UpdateExpression: "SET expiresAt = :e", ExpressionAttributeValues: { ":e": { N: String(Math.floor(Date.now() / 1000) - 60) } } }));
  r = await call("POST", "/api/survey-drafts/restore", draft(1, "qa-tc185-r9", { draftToken: t9 }));
  rec(S, "restore de un borrador caducado (fila aun presente)", { status: r.status, code: r.body?.code });
  const cookie = createSessionCookie({ sub: "qa-tc185-admin" }).split(";")[0];
  r = await call("GET", "/api/admin/survey-drafts", undefined, cookie);
  const items = Array.isArray(r.body) ? r.body : (r.body?.items ?? r.body?.drafts ?? []);
  rec(S, "el caducado en Progress", { aparece: items.some((i: any) => i.respondentId === "qa-tc185-r9") });
}

mkdirSync(OUT, { recursive: true });
writeFileSync(`${OUT}/api-scenarios-v2.json`, JSON.stringify(log, null, 2));
for (const [s, steps] of Object.entries(log)) { console.log(`\n## ${s}`); for (const st of steps) console.log("  ", JSON.stringify(st)); }
