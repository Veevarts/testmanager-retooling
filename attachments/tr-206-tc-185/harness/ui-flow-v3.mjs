// QA TC-185 v3 · IM-1302 · PR #92 (head 5656962f) — navegador REAL (Chromium), cliente, servidor y DynamoDB reales (local).
// Caminos nuevos: el desplazado recupera el borrador y envia; el desplazado cuando el otro YA envio;
// widget con cambio de definicion al enviar. Dos navegadores = dos contextos aislados.
// Uso: PW=<ruta a playwright/index.mjs> node ui-flow-v3.mjs <OUT> <cookie.json> <dir del server>
import { readFileSync, appendFileSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
const { chromium } = await import(process.env.PW);
const [OUT, COOKIE, SERVER] = process.argv.slice(2);
const U = "http://localhost:5287";
const url = (r) => `${U}/survey/qa-tc185-ui?clientOrgId=qa-org-tc185&respondentId=${r}&respondentName=QA%20${r}`;
const NET = `${OUT}/ui-red-v3.jsonl`; writeFileSync(NET, "");
const LOG = `${OUT}/ui-pasos-v3.jsonl`; writeFileSync(LOG, "");
const note = (step, data) => { appendFileSync(LOG, JSON.stringify({ step, ...data }) + "\n"); console.log(step, JSON.stringify(data).slice(0, 600)); };
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
  return { principal: rs.slice(0, 11).findIndex((x) => x.checked), texto: document.querySelector("textarea")?.value ?? null, avisos: alerts,
    continueHere: btns.includes("Continue here"),
    submitDeshabilitado: [...document.querySelectorAll("button")].find((x) => /submit/i.test(x.textContent))?.disabled ?? null,
    gracias: /thank/i.test(document.body.innerText),
    tokenEnLocalStorage: Object.keys(localStorage).filter((k) => /draft/i.test(k)).length };
});
const drafts = async (r) => { const d = await admin(`/api/admin/survey-drafts/3/qa-org-tc185/${r}`).catch(() => null); return d && d.status ? { status: d.status, score: d.score, comment: d.comment } : { status: "sin borrador activo" }; };
const responses = async (r) => (await admin(`/api/admin/responses`)).filter?.((x) => x.respondentId === r).map((x) => ({ score: x.score, comment: x.comment })) ?? null;
const newCtx = async (tag, withCookie = false) => { const c = await b.newContext({ viewport: { width: 1100, height: 900 } }); watch(c, tag); if (withCookie) await c.addCookies([{ name: cookie.name, value: cookie.value, domain: "localhost", path: "/", httpOnly: true }]); return c; };
const submit = async (p) => { await p.getByRole("button", { name: /^submit$/i }).click(); await p.waitForTimeout(3000); };

// ============ A · PAGINA: el desplazado envia, recupera con Continue here y envia; luego el otro ya no puede duplicar ============
{
  const R = "qa-tc185-ui20";
  const p1 = await (await newCtx("A-NAV1")).newPage();
  await p1.goto(url(R), { waitUntil: "networkidle" });
  await radios(p1).nth(6).check(); await p1.locator("textarea").fill("QA TC-185 v3 texto del navegador 1"); await p1.waitForTimeout(2500);
  const p2 = await (await newCtx("A-NAV2")).newPage();
  await p2.goto(url(R), { waitUntil: "networkidle" }); await radios(p2).nth(9).check(); await p2.waitForTimeout(2500);
  await p2.getByRole("button", { name: "Continue here" }).click(); await p2.waitForTimeout(2500);
  note("A1 · navegador 2 tomo el borrador", { servidor: await drafts(R) });
  await submit(p1);
  note("A2 · navegador 1 (desplazado, todo guardado) pulsa Submit", { ...(await state(p1)), servidor: await drafts(R), respuestas: await responses(R) }); await shot(p1, "v3-01-desplazado-envia-ve-el-aviso");
  await p1.getByRole("button", { name: "Continue here" }).click(); await p1.waitForTimeout(2500);
  note("A3 · navegador 1 pulsa Continue here", { ...(await state(p1)), servidor: await drafts(R) }); await shot(p1, "v3-02-desplazado-recupera");
  await submit(p1);
  note("A4 · navegador 1 envia", { ...(await state(p1)), respuestas: await responses(R) }); await shot(p1, "v3-03-desplazado-envia-ok");
  await submit(p2);
  note("A5 · navegador 2 (ahora desplazado, el otro YA envio) pulsa Submit", { ...(await state(p2)), servidor: await drafts(R), respuestas: await responses(R) }); await shot(p2, "v3-04-el-otro-ya-envio");
}

// ============ B · WIDGET: el desplazado envia, recupera y envia ============
const openWidget = (p, r) => p.evaluate((rr) => window.SurveyWidget.open({ featureId: "qa-tc185-ui", clientOrgId: "qa-org-tc185", respondentId: rr, respondentName: "QA " + rr }), r);
{
  const R = "qa-tc185-ui22";
  const w1 = await (await newCtx("B-W1", true)).newPage(); await w1.goto(`${U}/admin/features`, { waitUntil: "networkidle" }); await openWidget(w1, R); await w1.waitForTimeout(1500);
  await radios(w1).nth(7).check(); await w1.waitForTimeout(2500);
  const w2 = await (await newCtx("B-W2", true)).newPage(); await w2.goto(`${U}/admin/features`, { waitUntil: "networkidle" }); await openWidget(w2, R); await w2.waitForTimeout(1500);
  await radios(w2).nth(9).check(); await w2.waitForTimeout(2500);
  await w2.getByRole("button", { name: "Continue here" }).click(); await w2.waitForTimeout(2500);
  await submit(w1);
  note("B1 · widget 1 (desplazado) pulsa Submit", { ...(await state(w1)), servidor: await drafts(R), respuestas: await responses(R) }); await shot(w1, "v3-05-widget-desplazado-envia-ve-el-aviso");
  await w1.getByRole("button", { name: "Continue here" }).click(); await w1.waitForTimeout(2500);
  await submit(w1);
  note("B2 · widget 1 recupera y envia", { ...(await state(w1)), respuestas: await responses(R) }); await shot(w1, "v3-06-widget-desplazado-envia-ok");
}

// ============ C · WIDGET: el otro ya envio; el desplazado pulsa Submit y reintenta ============
{
  const R = "qa-tc185-ui21";
  const w1 = await (await newCtx("C-W1", true)).newPage(); await w1.goto(`${U}/admin/features`, { waitUntil: "networkidle" }); await openWidget(w1, R); await w1.waitForTimeout(1500);
  await radios(w1).nth(7).check(); await w1.waitForTimeout(2500);
  const w2 = await (await newCtx("C-W2", true)).newPage(); await w2.goto(`${U}/admin/features`, { waitUntil: "networkidle" }); await openWidget(w2, R); await w2.waitForTimeout(1500);
  await radios(w2).nth(9).check(); await w2.waitForTimeout(2500);
  await w2.getByRole("button", { name: "Continue here" }).click(); await w2.waitForTimeout(2500);
  await submit(w2);
  note("C1 · widget 2 envia", { respuestas: await responses(R) });
  await submit(w1);
  note("C2 · widget 1 (el otro ya envio) pulsa Submit", { ...(await state(w1)), respuestas: await responses(R) }); await shot(w1, "v3-07-widget-el-otro-ya-envio");
  await submit(w1);
  note("C3 · widget 1 reintenta Submit", { ...(await state(w1)), respuestas: await responses(R) });
  await radios(w1).nth(3).check(); await w1.waitForTimeout(2500); await submit(w1);
  note("C4 · widget 1 cambia la respuesta y envia otra vez", { ...(await state(w1)), respuestas: await responses(R) }); await shot(w1, "v3-08-widget-reintenta");
}

// ============ D · WIDGET: la definicion cambia antes de enviar (va el ULTIMO: cambia la encuesta) ============
{
  const R = "qa-tc185-ui23";
  const w = await (await newCtx("D-W", true)).newPage(); await w.goto(`${U}/admin/features`, { waitUntil: "networkidle" }); await openWidget(w, R); await w.waitForTimeout(1500);
  await radios(w).nth(8).check(); await w.waitForTimeout(2500);
  execSync(`bash -lc 'cd ${SERVER} && source qa-tc185/env.sh && npx tsx qa-tc185/change-def.ts 3'`, { stdio: "inherit" });
  await submit(w);
  note("D1 · widget envia tras un cambio real de definicion", { ...(await state(w)), respuestas: await responses(R) }); await shot(w, "v3-09-widget-definicion-cambiada");
  await submit(w);
  note("D2 · widget reintenta Submit", { ...(await state(w)), respuestas: await responses(R) }); await shot(w, "v3-10-widget-definicion-reintenta");
}
await b.close();
