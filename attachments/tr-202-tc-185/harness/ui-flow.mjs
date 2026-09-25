// QA TC-185 · recorrido de UI: navegador REAL (Chromium), cliente REAL, servidor REAL, DynamoDB REAL (local).
import { chromium } from "/private/tmp/claude-501/-Users-veevart-Desktop-testmanager-retooling/92c04aef-7c31-4c1c-93eb-b5e9022751ff/scratchpad/im-1297/fe/node_modules/playwright/index.mjs";
import { readFileSync, writeFileSync } from "node:fs";
const OUT = process.argv[2];
const U = "http://localhost:5287";
const url = (r, extra = "") => `${U}/survey/qa-tc185-ui?clientOrgId=qa-org-tc185&respondentId=${r}&respondentName=QA%20${r}${extra}`;
const cookie = JSON.parse(readFileSync(process.argv[3], "utf8"));
const log = [];
const note = (step, data) => { log.push({ step, ...data }); console.log(step, JSON.stringify(data)); };
const b = await chromium.launch({ headless: true });
const shot = (p, n) => p.screenshot({ path: `${OUT}/${n}.png`, fullPage: true });
const radios = (p) => p.locator("input[type=radio]");
const savedIndicator = (p) => p.evaluate(() => [...document.querySelectorAll("*")].map((e) => e.childElementCount === 0 ? e.textContent.trim() : "").find((t) => /sav/i.test(t)) ?? null);
const draftCalls = [];
function watch(ctx, tag) {
  ctx.on("request", (r) => { if (r.url().includes("/api/survey-drafts") || r.url().includes("/api/responses")) draftCalls.push({ tag, t: Date.now(), method: r.method(), path: new URL(r.url()).pathname, body: (() => { try { const j = JSON.parse(r.postData() ?? "{}"); return { saveSequence: j.saveSequence, score: j.score, comment: j.comment, companyRecommendScore: j.companyRecommendScore, hasToken: !!j.draftToken }; } catch { return null; } })() }); });
  ctx.on("response", async (r) => { if (r.url().includes("/api/survey-drafts") || r.url().includes("/api/responses")) { let code = null; try { code = (await r.json())?.code ?? null; } catch {} draftCalls.push({ tag, t: Date.now(), status: r.status(), path: new URL(r.url()).pathname, code }); } });
}

// ===== Encuestado A (ui1): contesta, cierra, reabre =====
const ctxA = await b.newContext({ viewport: { width: 1100, height: 900 } }); watch(ctxA, "A");
let p = await ctxA.newPage();
await p.goto(url("qa-tc185-ui1"), { waitUntil: "networkidle" });
await shot(p, "01-abre-encuesta");
let w = p.waitForResponse((r) => r.url().endsWith("/api/survey-drafts") && r.request().method() === "POST");
await radios(p).nth(9).check();
let r = await w; await p.waitForTimeout(400);
note("02 · primera respuesta (9)", { status: r.status(), indicador: await savedIndicator(p) });
await shot(p, "02-primera-respuesta-autosave");
w = p.waitForResponse((r) => r.url().endsWith("/api/survey-drafts") && r.request().method() === "POST");
await p.locator("textarea").fill("QA TC-185 motivo parcial");
r = await w; await p.waitForTimeout(400);
note("03 · segunda respuesta (texto)", { status: r.status(), indicador: await savedIndicator(p) });
await shot(p, "03-segunda-respuesta-autosave");
const key = await p.evaluate(() => Object.keys(localStorage).filter((k) => /draft/i.test(k)));
note("token en localStorage", { claves: key, longitudToken: key[0] ? (await p.evaluate((k) => localStorage.getItem(k)?.length, key[0])) : null });

// AC2 · cambio y cierre inmediato, dentro del debounce
const before = draftCalls.length;
await radios(p).nth(11 + 7).check();          // empresa: 7
await p.close({ runBeforeUnload: true });      // cierra la pestana sin esperar al debounce
await new Promise((res) => setTimeout(res, 1500));
note("AC2 · peticiones tras cerrar", { nuevas: draftCalls.slice(before) });

// Reabre en el MISMO navegador
p = await ctxA.newPage();
await p.goto(url("qa-tc185-ui1"), { waitUntil: "networkidle" }); await p.waitForTimeout(600);
const restored = await p.evaluate(() => { const rs = [...document.querySelectorAll("input[type=radio]")]; return { principal: rs.slice(0, 11).findIndex((x) => x.checked), empresa: rs.slice(11).findIndex((x) => x.checked), texto: document.querySelector("textarea")?.value }; });
note("04 · reabre y restaura", { restaurado: restored, indicador: await savedIndicator(p) });
await shot(p, "04-reabre-restaurado");

// ===== Admin: Progress antes del envio =====
const ctxAdmin = await b.newContext({ viewport: { width: 1400, height: 900 } });
await ctxAdmin.addCookies([{ name: cookie.name, value: cookie.value, domain: "localhost", path: "/", httpOnly: true }]);
const pa = await ctxAdmin.newPage();
await pa.goto(`${U}/admin/dashboard`, { waitUntil: "networkidle" }); await pa.waitForTimeout(800);
const tabs = await pa.evaluate(() => [...document.querySelectorAll("button,[role=tab],a")].map((e) => (e.innerText || "").trim()).filter(Boolean).slice(0, 40));
note("admin · pestanas visibles", { tabs });
const prog = pa.getByRole("tab", { name: /progress/i }).or(pa.getByRole("button", { name: /^progress$/i })).first();
await prog.click(); await pa.waitForTimeout(1200);
await shot(pa, "05-admin-progress-antes-del-envio");
const progText = await pa.evaluate(() => document.body.innerText);
note("05 · Progress antes del envio", { muestraUi1: progText.includes("qa-tc185-ui1") || progText.includes("QA qa-tc185-ui1"), extracto: progText.split("\n").filter((l) => /ui1|answered|resume|step|saved|started/i.test(l)).slice(0, 14) });
writeFileSync(`${OUT}/admin-progress.txt`, progText);

// Detalle
const row = pa.getByText(/qa-tc185-ui1/).first();
if (await row.count()) { await row.click(); await pa.waitForTimeout(900); }
await shot(pa, "06-admin-detalle-borrador");
const det = await pa.evaluate(() => document.body.innerText);
writeFileSync(`${OUT}/admin-detalle.txt`, det);
note("06 · detalle", { extracto: det.split("\n").filter((l) => /answered|unanswered|not answered|no answer|recommend|reason|QA TC-185/i.test(l)).slice(0, 16) });
await pa.keyboard.press("Escape");

// ===== Envio =====
w = p.waitForResponse((r) => r.url().includes("/api/responses") && r.request().method() === "POST");
await p.getByRole("button", { name: /submit/i }).click();
r = await w; await p.waitForTimeout(800);
note("07 · envio", { status: r.status() });
await shot(p, "07-envio");
const keyAfter = await p.evaluate(() => Object.keys(localStorage).filter((k) => /draft/i.test(k)));
note("token tras el envio", { claves: keyAfter });

await pa.reload({ waitUntil: "networkidle" }); await pa.waitForTimeout(600);
await prog.click().catch(() => {}); await pa.getByRole("tab", { name: /progress/i }).or(pa.getByRole("button", { name: /^progress$/i })).first().click().catch(() => {});
await pa.waitForTimeout(1000);
const progAfter = await pa.evaluate(() => document.body.innerText);
note("08 · Progress tras el envio", { muestraUi1: progAfter.includes("qa-tc185-ui1") });
await shot(pa, "08-admin-progress-tras-el-envio");

// ===== Segundo navegador: mismo encuestado (ui3), otro navegador =====
const ctxB1 = await b.newContext(); watch(ctxB1, "B1");
const pb1 = await ctxB1.newPage();
await pb1.goto(url("qa-tc185-ui3"), { waitUntil: "networkidle" });
w = pb1.waitForResponse((r) => r.url().endsWith("/api/survey-drafts"));
await radios(pb1).nth(6).check(); await w; await pb1.waitForTimeout(500);
note("SN · navegador 1 empieza", { ok: true });
const ctxB2 = await b.newContext({ viewport: { width: 1100, height: 900 } }); watch(ctxB2, "B2");
const pb2 = await ctxB2.newPage();
await pb2.goto(url("qa-tc185-ui3"), { waitUntil: "networkidle" }); await pb2.waitForTimeout(500);
await shot(pb2, "09-segundo-navegador-abre");
await radios(pb2).nth(10).check(); await pb2.waitForTimeout(1800);
await pb2.locator("textarea").fill("QA TC-185 desde otro navegador"); await pb2.waitForTimeout(1800);
await shot(pb2, "10-segundo-navegador-contesta");
w = pb2.waitForResponse((r) => r.url().includes("/api/responses") && r.request().method() === "POST");
await pb2.getByRole("button", { name: /submit/i }).click();
r = await w; await pb2.waitForTimeout(1200);
await shot(pb2, "11-segundo-navegador-envia");
const visible = await pb2.evaluate(() => document.body.innerText);
note("SN · navegador 2 envia", { status: r.status(), loQueVe: visible.split("\n").filter(Boolean).slice(0, 12) });

// ===== Vista previa =====
const ctxP = await b.newContext(); watch(ctxP, "PREVIEW");
const pp = await ctxP.newPage();
await pp.goto(url("qa-tc185-ui5", "&preview=1"), { waitUntil: "networkidle" });
await radios(pp).nth(8).check(); await pp.locator("textarea").fill("preview"); await pp.waitForTimeout(2500);
note("preview", { peticionesDeBorrador: draftCalls.filter((c) => c.tag === "PREVIEW" && c.path?.includes("survey-drafts")).length, localStorage: await pp.evaluate(() => Object.keys(localStorage).filter((k) => /draft/i.test(k))) });
await shot(pp, "12-vista-previa");

writeFileSync(`${OUT}/ui-flow.json`, JSON.stringify({ log, red: draftCalls }, null, 2));
await b.close();
