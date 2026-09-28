import { chromium } from "<scratchpad>/im-1297/fe/node_modules/playwright/index.mjs";
import { readFileSync, appendFileSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
const [OUT, COOKIE, SERVER] = process.argv.slice(2);
const U = "http://localhost:5287";
const url = (r, extra = "") => `${U}/survey/qa-tc185-ui?clientOrgId=qa-org-tc185&respondentId=${r}&respondentName=QA%20${r}${extra}`;
const NET = `${OUT}/red-ac4.jsonl`; writeFileSync(NET, "");
const LOG = `${OUT}/ac4.jsonl`; writeFileSync(LOG, "");
const note = (step, data) => { appendFileSync(LOG, JSON.stringify({ step, ...data }) + "\n"); console.log(step, JSON.stringify(data).slice(0, 400)); };
function watch(ctx, tag) {
  ctx.on("request", (r) => { const u = r.url(); if (u.includes("/api/survey-drafts") || u.includes("/api/responses")) { let b = null; try { const j = JSON.parse(r.postData() ?? "{}"); b = { seq: j.saveSequence, score: j.score, comment: j.comment, token: j.draftToken ? j.draftToken.slice(0, 6) + "…" : null }; } catch {} appendFileSync(NET, JSON.stringify({ tag, kind: "req", method: r.method(), path: new URL(u).pathname, b }) + "\n"); } });
  ctx.on("response", async (r) => { const u = r.url(); if (u.includes("/api/survey-drafts") || u.includes("/api/responses")) { let body = null; try { body = await r.json(); } catch {} appendFileSync(NET, JSON.stringify({ tag, kind: "res", status: r.status(), path: new URL(u).pathname, code: body?.code ?? null, error: body?.error ?? null }) + "\n"); } });
}
const b = await chromium.launch({ headless: true });
const shot = (p, n) => p.screenshot({ path: `${OUT}/${n}.png`, fullPage: true });
const radios = (p) => p.locator("input[type=radio]");
const state = (p) => p.evaluate(() => { const rs = [...document.querySelectorAll("input[type=radio]")]; const alert = [...document.querySelectorAll("div,p,span")].find((e) => e.childElementCount === 0 && /changed|fresh attempt|could not|error|failed|try again/i.test(e.textContent || "")); return { principal: rs.slice(0, 11).findIndex((x) => x.checked), texto: document.querySelector("textarea")?.value ?? null, aviso: alert?.textContent?.trim() ?? null, submitDeshabilitado: document.querySelector("button[type=submit]")?.disabled ?? null, token: Object.keys(localStorage).filter((k) => /draft/i.test(k)).length }; });

// ===== AC4 · cambio REAL de definicion, para comparar el mensaje =====
const c3 = await b.newContext({ viewport: { width: 1100, height: 900 } }); watch(c3, "AC4");
const p3 = await c3.newPage();
await p3.goto(url("qa-tc185-ui7"), { waitUntil: "networkidle" });
await radios(p3).nth(8).check(); await p3.locator("textarea").fill("QA TC-185 antes del cambio"); await p3.waitForTimeout(2500);
note("AC4a · borrador creado", await state(p3));
await p3.close();
execSync(`bash -lc 'cd ${SERVER} && source qa-tc185/env.sh && npx tsx qa-tc185/change-def.ts 3'`, { stdio: "inherit" });
const p3b = await c3.newPage();
await p3b.goto(url("qa-tc185-ui7"), { waitUntil: "networkidle" }); await p3b.waitForTimeout(1500);
note("AC4b · reabre tras el cambio real", await state(p3b)); await shot(p3b, "13-definicion-cambiada");

await b.close();
