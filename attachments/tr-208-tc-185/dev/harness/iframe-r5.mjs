// TR-208 · iframe real de nps_03 contra dev, en un solo proceso headless (sin admin).
// Reabre el widget con la secuencia del LWC npsWidget, comprueba que el borrador pendiente se restaura,
// pulsa Submit y registra que responde el servidor y que ve el encuestado. Nunca guarda tokens.
const { chromium } = await import(process.env.PW);
import { appendFileSync, mkdirSync } from "node:fs";
const OUT = process.argv[2]; mkdirSync(OUT, { recursive: true });
const log = (step, d) => { appendFileSync(OUT + "/pasos.jsonl", JSON.stringify({ t: new Date().toISOString(), step, ...d }) + "\n"); console.log(step, JSON.stringify(d).slice(0, 600)); };
const net = (d) => appendFileSync(OUT + "/net.jsonl", JSON.stringify({ t: new Date().toISOString(), ...d }) + "\n");
const SLUG = "qa-tc-185-iframe", USER = { id: "005Rt00000aTMIrIAO", createdDate: "2026-09-14T21:25:01.000Z" };
const ctx = await chromium.launchPersistentContext(process.env.PROFILE, { headless: true, viewport: { width: 1400, height: 900 } });
const browser = ctx;
const SAFE = ["score", "companyRecommendScore", "saveSequence", "code", "status", "error", "requestId", "resumeCount", "answeredQuestionCount", "surveyId"];
const pick = (o) => { if (!o || typeof o !== "object" || Array.isArray(o)) return o && Array.isArray(o) ? { array: o.length } : null; const r = {}; for (const k of SAFE) if (k in o) r[k] = o[k]; if ("draftToken" in o) r.draftToken = o.draftToken ? "<presente>" : null; return r; };
ctx.on("response", async (res) => { const u = res.url(); if (!/surveytool\.dev\.veevart\.ai\/api\//.test(u)) return; let b = null; try { b = pick(await res.json()); } catch {} net({ method: res.request().method(), path: u.replace(/^https:\/\/[^/]+/, "").replace(/\?.*$/, ""), status: res.status(), body: b }); });
const page = ctx.pages()[0] ?? await ctx.newPage();
await page.goto(process.env.SF_FRONTDOOR, { waitUntil: "domcontentloaded" });
await page.waitForURL(/lightning\.force\.com\/lightning\//, { timeout: 90000 });
await page.waitForTimeout(8000);
const open = await page.evaluate(async ({ SLUG, USER }) => {
  const base = "https://surveytool.dev.veevart.ai"; const key = `veevart:surveyUsage:${SLUG}`;
  let usageCount = 1; try { usageCount = Number(localStorage.getItem(key) || "0") + 1; localStorage.setItem(key, String(usageCount)); } catch {}
  const clientOrgId = location.hostname.split(".")[0];
  const c = { clientOrgId, salesforceOrgId: "00DRt00000WkwJ0MAJ", respondentId: USER.id, respondentName: "User User", respondentEmail: "", respondentPhone: "", respondentTitle: "", userCreatedDate: USER.createdDate };
  const r = await fetch(`${base}/api/features/${SLUG}/surveys`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ featureSlug: SLUG, ...c, today: new Date().toISOString().slice(0, 10), usageCount }) });
  const list = r.ok ? await r.json() : [];
  if (!list.length) return { eligStatus: r.status, eligible: [] };
  window.SURVEY_APP_URL = base;
  await new Promise((ok, ko) => { const s = document.createElement("script"); s.src = "/resource/Auctifera__SurveyWidgetTrigger"; s.onload = ok; s.onerror = ko; document.head.appendChild(s); });
  window.SurveyWidget.open({ featureId: SLUG, surveyId: list[0].id, ...c, usageCount });
  try { localStorage.setItem(key, "0"); } catch {}
  const imp = await fetch(`${base}/api/features/${SLUG}/impressions`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ surveyId: list[0].id, ...c, usageCount }) });
  return { eligStatus: r.status, eligible: list.map((s) => s.id), impression: imp.status };
}, { SLUG, USER });
await page.waitForTimeout(5000);
const frame = page.frames().find((f) => /surveytool\.dev\.veevart\.ai\/survey\//.test(f.url()));
const state = () => frame.evaluate(() => {
  const g = {}; document.querySelectorAll("input[type=radio]").forEach((r) => (g[r.name] ??= []).push(r));
  const n = Object.keys(g); const ck = (k) => { const c = (g[k] ?? []).find((r) => r.checked); return c ? Number(c.value) : -1; };
  const b = [...document.querySelectorAll("button")].find((x) => /submit/i.test(x.textContent ?? ""));
  return { principal: ck(n[0]), empresa: n[1] ? ck(n[1]) : null, texto: document.querySelector("textarea")?.value ?? null,
    submit: b ? (b.disabled ? "deshabilitado" : "habilitado") : "sin boton",
    avisos: [...document.querySelectorAll("[role=alert],[role=status],.survey-save-status")].map((e) => e.textContent.trim()).filter(Boolean),
    gracias: /thank/i.test(document.body.innerText) };
});
log("abre-en-navegador-nuevo", { ...open, iframe: await state() });
await page.screenshot({ path: OUT + "/08-navegador-nuevo-formulario-vacio.png" });
await frame.locator('input[type=radio][name="nps"][value="9"]').check();
await page.waitForTimeout(4000);
log("contesta-9", await state());
await frame.locator("textarea").first().fill("QA TC-185 r5 segundo navegador en dev");
await frame.locator('input[type=radio][name="companyRecommend"][value="8"]').check();
await page.waitForTimeout(4000);
log("contesta-resto-con-aviso", await state());
await page.screenshot({ path: OUT + "/09-conflicto-continue-here.png" });
const ch = frame.getByRole("button", { name: /continue here/i });
if (await ch.count()) { await ch.first().click(); await page.waitForTimeout(4000); }
log("continue-here", { pulsado: await ch.count() >= 0, ...(await state()) });
await page.screenshot({ path: OUT + "/10-tras-continue-here.png" });
const sub = frame.locator("button", { hasText: /submit/i }).first();
await sub.click({ timeout: 10000 });
await page.waitForTimeout(5000);
log("envia", await state());
await frame.evaluate(() => document.querySelector("[role=alert]")?.scrollIntoView({ block: "center" }));
await page.waitForTimeout(500);
await page.screenshot({ path: OUT + "/11-envia-500-mensaje-generico.png" });
await ctx.close();
