// QA TC-185 v2 · IM-1302 · PR #91 (merge 3789cb5c) — navegador REAL (Chromium), cliente, servidor y DynamoDB reales (local).
// Dos navegadores = dos contextos de Playwright aislados (localStorage propio), como dos maquinas.
import { chromium } from "<scratchpad>/im-1297/fe/node_modules/playwright/index.mjs";
import { readFileSync, appendFileSync, writeFileSync } from "node:fs";
const [OUT, COOKIE] = process.argv.slice(2);
const U = "http://localhost:5287";
const url = (r) => `${U}/survey/qa-tc185-ui?clientOrgId=qa-org-tc185&respondentId=${r}&respondentName=QA%20${r}`;
const NET = `${OUT}/ui-red-v2.jsonl`; writeFileSync(NET, "");
const LOG = `${OUT}/ui-pasos-v2.jsonl`; writeFileSync(LOG, "");
const note = (step, data) => { appendFileSync(LOG, JSON.stringify({ step, ...data }) + "\n"); console.log(step, JSON.stringify(data).slice(0, 500)); };
function watch(ctx, tag) {
  ctx.on("request", (r) => { const u = r.url(); if (u.includes("/api/survey-drafts") || u.includes("/api/responses")) { let b = null; try { const j = JSON.parse(r.postData() ?? "{}"); b = { seq: j.saveSequence, score: j.score, comment: j.comment, replace: j.replaceExistingDraft ?? null, token: j.draftToken ? "si" : "no" }; } catch {} appendFileSync(NET, JSON.stringify({ tag, kind: "req", method: r.method(), path: new URL(u).pathname, b }) + "\n"); } });
  ctx.on("response", async (r) => { const u = r.url(); if (u.includes("/api/survey-drafts") || u.includes("/api/responses")) { let body = null; try { body = await r.json(); } catch {} appendFileSync(NET, JSON.stringify({ tag, kind: "res", status: r.status(), path: new URL(u).pathname, code: body?.code ?? null, error: body?.error ?? null }) + "\n"); } });
}
const cookie = JSON.parse(readFileSync(COOKIE, "utf8"));
const admin = async (path) => (await fetch(`http://localhost:4599${path}`, { headers: { cookie: `${cookie.name}=${cookie.value}` } })).json();
const b = await chromium.launch({ headless: true });
const shot = (p, n) => p.screenshot({ path: `${OUT}/${n}.png`, fullPage: true });
const radios = (p) => p.locator("input[type=radio]");
const state = (p) => p.evaluate(() => {
  const rs = [...document.querySelectorAll("input[type=radio]")];
  const alerts = [...document.querySelectorAll("[role=alert]")].map((e) => e.innerText.trim()).filter(Boolean);
  const btns = [...document.querySelectorAll("button")].map((x) => x.textContent.trim()).filter(Boolean);
  return { principal: rs.slice(0, 11).findIndex((x) => x.checked), empresa: rs.slice(11, 22).findIndex((x) => x.checked),
    texto: document.querySelector("textarea")?.value ?? null, avisos: alerts,
    dice_que_la_encuesta_cambio: /survey changed/i.test(document.body.innerText),
    continueHere: btns.includes("Continue here"),
    submitDeshabilitado: [...document.querySelectorAll("button")].find((x) => /submit/i.test(x.textContent))?.disabled ?? null,
    gracias: /thank/i.test(document.body.innerText),
    tokenEnLocalStorage: Object.keys(localStorage).filter((k) => /draft/i.test(k)).length };
});
const drafts = async (r) => { const d = await admin(`/api/admin/survey-drafts/3/qa-org-tc185/${r}`).catch(() => null); return d && { status: d.status, score: d.score, comment: d.comment, companyRecommendScore: d.companyRecommendScore, saveSequence: d.saveSequence, resumeCount: d.resumeCount }; };
const responses = async (r) => (await admin(`/api/admin/responses`)).filter?.((x) => x.respondentId === r).map((x) => ({ score: x.score, comment: x.comment })) ?? null;
const newCtx = async (tag) => { const c = await b.newContext({ viewport: { width: 1100, height: 900 } }); watch(c, tag); return c; };

// ============ S6 · PAGINA DIRECTA: el mismo encuestado en dos navegadores ============
const R = "qa-tc185-ui6";
const c1 = await newCtx("NAV1"); const p1 = await c1.newPage();
await p1.goto(url(R), { waitUntil: "networkidle" });
await radios(p1).nth(6).check(); await p1.locator("textarea").fill("QA TC-185 texto del navegador 1"); await p1.waitForTimeout(2500);
note("01 · navegador 1 contesta 6 + texto (autosave)", { ...(await state(p1)), servidor: await drafts(R) }); await shot(p1, "v2-01-navegador1-contesta");
const c2 = await newCtx("NAV2"); const p2 = await c2.newPage();
await p2.goto(url(R), { waitUntil: "networkidle" }); await p2.waitForTimeout(1000);
note("02 · navegador 2 abre (sin token)", await state(p2)); await shot(p2, "v2-02-navegador2-abre");
await radios(p2).nth(10).check(); await p2.waitForTimeout(2500);
note("03 · navegador 2 contesta 10: autosave -> conflicto", { ...(await state(p2)), servidor: await drafts(R) }); await shot(p2, "v2-03-navegador2-conflicto");
await p2.locator("textarea").fill("QA TC-185 escrito en el navegador 2 con el aviso visible"); await radios(p2).nth(11 + 9).check(); await p2.waitForTimeout(2500);
note("04 · navegador 2 sigue contestando con el aviso visible", { ...(await state(p2)), servidor: await drafts(R) }); await shot(p2, "v2-04-navegador2-sigue-con-aviso");
const sub2 = p2.getByRole("button", { name: /submit/i });
note("05a · Submit antes de Continue here", { deshabilitado: await sub2.isDisabled() });
if (!(await sub2.isDisabled())) { await sub2.click(); await p2.waitForTimeout(2500); }
note("05b · tras pulsar Submit sin Continue here", { ...(await state(p2)), servidor: await drafts(R), respuestas: await responses(R) }); await shot(p2, "v2-05-navegador2-submit-sin-continuar");
await p2.getByRole("button", { name: "Continue here" }).click(); await p2.waitForTimeout(2500);
note("06 · navegador 2 pulsa Continue here", { ...(await state(p2)), servidor: await drafts(R) }); await shot(p2, "v2-06-navegador2-continue-here");
// Navegador 1, desplazado, con todo guardado y sin cambios pendientes, pulsa Submit
note("07a · navegador 1 antes de enviar (desplazado)", await state(p1)); await shot(p1, "v2-07-navegador1-desplazado-antes-de-enviar");
await p1.getByRole("button", { name: /submit/i }).click(); await p1.waitForTimeout(3000);
note("07b · navegador 1 (desplazado) pulsa Submit", { ...(await state(p1)), servidor: await drafts(R), respuestas: await responses(R) }); await shot(p1, "v2-08-navegador1-desplazado-envia");
// Navegador 2 envia
await p2.getByRole("button", { name: /submit/i }).click(); await p2.waitForTimeout(3000);
note("08 · navegador 2 envia", { ...(await state(p2)), servidor: await drafts(R), respuestas: await responses(R) }); await shot(p2, "v2-09-navegador2-envia");

// ============ S6b · el desplazado CAMBIA algo antes de enviar ============
const R2 = "qa-tc185-ui9";
const d1 = await newCtx("DESPL1"); const q1 = await d1.newPage();
await q1.goto(url(R2), { waitUntil: "networkidle" }); await radios(q1).nth(3).check(); await q1.waitForTimeout(2500);
const d2 = await newCtx("DESPL2"); const q2 = await d2.newPage();
await q2.goto(url(R2), { waitUntil: "networkidle" }); await radios(q2).nth(8).check(); await q2.waitForTimeout(2500);
await q2.getByRole("button", { name: "Continue here" }).click(); await q2.waitForTimeout(2000);
await radios(q1).nth(4).check(); await q1.waitForTimeout(2500);
note("09 · el desplazado cambia su respuesta (autosave)", { ...(await state(q1)), servidor: await drafts(R2) }); await shot(q1, "v2-10-desplazado-cambia-y-ve-el-aviso");

// ============ S6c · lo escrito con el aviso visible, cerrar justo tras Continue here ============
const R3 = "qa-tc185-ui10";
const e1 = await newCtx("STALE1"); const s1 = await e1.newPage();
await s1.goto(url(R3), { waitUntil: "networkidle" }); await radios(s1).nth(5).check(); await s1.waitForTimeout(2500);
const e2 = await newCtx("STALE2"); const s2 = await e2.newPage();
await s2.goto(url(R3), { waitUntil: "networkidle" }); await radios(s2).nth(9).check(); await s2.waitForTimeout(2500);
await s2.locator("textarea").fill("QA TC-185 escrito durante el aviso"); await s2.waitForTimeout(800);
await s2.getByRole("button", { name: "Continue here" }).click(); await s2.waitForTimeout(2500);
note("10a · Continue here con texto escrito durante el aviso", { ...(await state(s2)), servidor: await drafts(R3) });
await s2.close(); await s1.waitForTimeout(1500);
const s2b = await e2.newPage(); await s2b.goto(url(R3), { waitUntil: "networkidle" }); await s2b.waitForTimeout(1500);
note("10b · cierra y reabre en el navegador 2", { ...(await state(s2b)), servidor: await drafts(R3) }); await shot(s2b, "v2-11-reabre-tras-continue-here");

// ============ S6d · WIDGET embebido (SurveyWidget) ============
const R4 = "qa-tc185-ui12";
const openWidget = (p) => p.evaluate((r) => window.SurveyWidget.open({ featureId: "qa-tc185-ui", clientOrgId: "qa-org-tc185", respondentId: r, respondentName: "QA " + r }), R4);
const w1c = await newCtx("W1"); await w1c.addCookies([{ name: cookie.name, value: cookie.value, domain: "localhost", path: "/", httpOnly: true }]);
const w1 = await w1c.newPage(); await w1.goto(`${U}/admin/features`, { waitUntil: "networkidle" }); await openWidget(w1); await w1.waitForTimeout(1500);
await radios(w1).nth(7).check(); await w1.waitForTimeout(2500);
note("11 · widget navegador 1 contesta 7", { ...(await state(w1)), servidor: await drafts(R4) }); await shot(w1, "v2-12-widget-navegador1");
const w2c = await newCtx("W2"); await w2c.addCookies([{ name: cookie.name, value: cookie.value, domain: "localhost", path: "/", httpOnly: true }]);
const w2 = await w2c.newPage(); await w2.goto(`${U}/admin/features`, { waitUntil: "networkidle" }); await openWidget(w2); await w2.waitForTimeout(1500);
await radios(w2).nth(9).check(); await w2.waitForTimeout(2500);
note("12 · widget navegador 2 contesta 9 -> conflicto", { ...(await state(w2)), servidor: await drafts(R4) }); await shot(w2, "v2-13-widget-navegador2-conflicto");
await w2.getByRole("button", { name: "Continue here" }).click(); await w2.waitForTimeout(2500);
note("13 · widget navegador 2 Continue here", { ...(await state(w2)), servidor: await drafts(R4) }); await shot(w2, "v2-14-widget-navegador2-continue-here");
await w1.getByRole("button", { name: /submit/i }).click(); await w1.waitForTimeout(3000);
note("14 · widget navegador 1 (desplazado) Submit", { ...(await state(w1)), servidor: await drafts(R4), respuestas: await responses(R4) }); await shot(w1, "v2-15-widget-desplazado-envia");
await w2.getByRole("button", { name: /submit/i }).click(); await w2.waitForTimeout(3000);
note("15 · widget navegador 2 Submit", { ...(await state(w2)), servidor: await drafts(R4), respuestas: await responses(R4) }); await shot(w2, "v2-16-widget-navegador2-envia");
await b.close();
