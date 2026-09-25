import { chromium } from "/private/tmp/claude-501/-Users-veevart-Desktop-testmanager-retooling/92c04aef-7c31-4c1c-93eb-b5e9022751ff/scratchpad/im-1297/fe/node_modules/playwright/index.mjs";
import { readFileSync, appendFileSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
const [OUT, COOKIE, SERVER] = process.argv.slice(2);
const U = "http://localhost:5287";
const url = (r, extra = "") => `${U}/survey/qa-tc185-ui?clientOrgId=qa-org-tc185&respondentId=${r}&respondentName=QA%20${r}${extra}`;
const NET = `${OUT}/red-flow2.jsonl`; writeFileSync(NET, "");
const LOG = `${OUT}/flow2.jsonl`; writeFileSync(LOG, "");
const note = (step, data) => { appendFileSync(LOG, JSON.stringify({ step, ...data }) + "\n"); console.log(step, JSON.stringify(data).slice(0, 400)); };
function watch(ctx, tag) {
  ctx.on("request", (r) => { const u = r.url(); if (u.includes("/api/survey-drafts") || u.includes("/api/responses")) { let b = null; try { const j = JSON.parse(r.postData() ?? "{}"); b = { seq: j.saveSequence, score: j.score, comment: j.comment, token: j.draftToken ? j.draftToken.slice(0, 6) + "…" : null }; } catch {} appendFileSync(NET, JSON.stringify({ tag, kind: "req", method: r.method(), path: new URL(u).pathname, b }) + "\n"); } });
  ctx.on("response", async (r) => { const u = r.url(); if (u.includes("/api/survey-drafts") || u.includes("/api/responses")) { let body = null; try { body = await r.json(); } catch {} appendFileSync(NET, JSON.stringify({ tag, kind: "res", status: r.status(), path: new URL(u).pathname, code: body?.code ?? null, error: body?.error ?? null }) + "\n"); } });
}
const b = await chromium.launch({ headless: true });
const shot = (p, n) => p.screenshot({ path: `${OUT}/${n}.png`, fullPage: true });
const radios = (p) => p.locator("input[type=radio]");
const state = (p) => p.evaluate(() => { const rs = [...document.querySelectorAll("input[type=radio]")]; const alert = [...document.querySelectorAll("div,p,span")].find((e) => e.childElementCount === 0 && /changed|fresh attempt|could not|error|failed|try again/i.test(e.textContent || "")); return { principal: rs.slice(0, 11).findIndex((x) => x.checked), texto: document.querySelector("textarea")?.value ?? null, aviso: alert?.textContent?.trim() ?? null, submitDeshabilitado: document.querySelector("button[type=submit]")?.disabled ?? null, token: Object.keys(localStorage).filter((k) => /draft/i.test(k)).length }; });

// ===== Detalle de admin via View =====
const cookie = JSON.parse(readFileSync(COOKIE, "utf8"));
const cA = await b.newContext({ viewport: { width: 1400, height: 1000 } });
await cA.addCookies([{ name: cookie.name, value: cookie.value, domain: "localhost", path: "/", httpOnly: true }]);
const pa = await cA.newPage();
await pa.goto(`${U}/admin/dashboard`, { waitUntil: "networkidle" });
await pa.getByRole("button", { name: /^progress$/i }).or(pa.getByRole("tab", { name: /progress/i })).first().click(); await pa.waitForTimeout(1000);
await pa.getByRole("row", { name: /qa-tc185-r1/ }).getByRole("button", { name: /view/i }).click(); await pa.waitForTimeout(1000);
await shot(pa, "06-admin-detalle-borrador");
const det = await pa.evaluate(() => (document.querySelector("[role=dialog]") ?? document.body).innerText);
writeFileSync(`${OUT}/admin-detalle.txt`, det);
note("06 · detalle via View", { lineas: det.split("\n").filter(Boolean).slice(0, 24) });

// ===== Segundo navegador, paso a paso =====
const c1 = await b.newContext(); watch(c1, "NAV1");
const p1 = await c1.newPage();
await p1.goto(url("qa-tc185-ui6"), { waitUntil: "networkidle" });
await radios(p1).nth(6).check(); await p1.waitForTimeout(2500);
note("SN1 · navegador 1 contesta 6", await state(p1));
const c2 = await b.newContext({ viewport: { width: 1100, height: 900 } }); watch(c2, "NAV2");
const p2 = await c2.newPage();
await p2.goto(url("qa-tc185-ui6"), { waitUntil: "networkidle" }); await p2.waitForTimeout(1000);
note("SN2 · navegador 2 abre", await state(p2)); await shot(p2, "09-segundo-navegador-abre");
await radios(p2).nth(10).check(); await p2.waitForTimeout(2500);
note("SN3 · navegador 2 contesta 10 y espera el autosave", await state(p2)); await shot(p2, "10-segundo-navegador-contesta");
await radios(p2).nth(10).check(); await p2.locator("textarea").fill("QA TC-185 segundo intento"); await p2.waitForTimeout(2500);
note("SN4 · vuelve a contestar", await state(p2)); await shot(p2, "11-segundo-navegador-reintenta");
const btn = p2.getByRole("button", { name: /submit/i });
note("SN5 · boton Submit", { deshabilitado: await btn.isDisabled() });
if (!(await btn.isDisabled())) { await btn.click(); await p2.waitForTimeout(2500); }
note("SN6 · tras pulsar Submit", await state(p2)); await shot(p2, "12-segundo-navegador-envia");

// ===== AC4 · cambio REAL de definicion, para comparar el mensaje =====
const c3 = await b.newContext({ viewport: { width: 1100, height: 900 } }); watch(c3, "AC4");
const p3 = await c3.newPage();
await p3.goto(url("qa-tc185-ui7"), { waitUntil: "networkidle" });
await radios(p3).nth(8).check(); await p3.locator("textarea").fill("QA TC-185 antes del cambio"); await p3.waitForTimeout(2500);
note("AC4a · borrador creado", await state(p3));
await p3.close();
execSync(`bash -lc 'cd ${SERVER} && source qa-tc185/env.sh && npx tsx qa-tc185/change-def.ts 4'`, { stdio: "inherit" });
const p3b = await c3.newPage();
await p3b.goto(url("qa-tc185-ui7"), { waitUntil: "networkidle" }); await p3b.waitForTimeout(1500);
note("AC4b · reabre tras el cambio real", await state(p3b)); await shot(p3b, "13-definicion-cambiada");

// ===== Vista previa =====
const c4 = await b.newContext(); watch(c4, "PREVIEW");
const p4 = await c4.newPage();
await p4.goto(url("qa-tc185-ui8", "&preview=1"), { waitUntil: "networkidle" });
await radios(p4).nth(8).check(); await p4.locator("textarea").fill("preview"); await p4.waitForTimeout(3000);
note("PREVIEW · tras contestar", await state(p4)); await shot(p4, "14-vista-previa");
await b.close();
