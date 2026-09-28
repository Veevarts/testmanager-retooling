// Escenario 12 · el widget de Survey Tool DENTRO de Salesforce (nps_03), con la secuencia exacta del LWC
// Auctifera npsWidget: POST de elegibilidad -> SURVEY_APP_URL -> recurso estatico Auctifera__SurveyWidgetTrigger
// -> SurveyWidget.open({...contexto del usuario}) -> POST de impresion.
// Uso: node widget.mjs <accion> [args]
//   open | state | score <n> | reason <texto> | company <n> | close | submit | shot <fichero> | storage
import { connect, findPage, shot } from "./lib.mjs";
import { appendFileSync } from "node:fs";

const SLUG = "qa-tc-185-iframe";
const USER = { id: "005Rt00000aTMIrIAO", createdDate: "2026-09-14T21:25:01.000Z" }; // User User de nps_03
const { ctx } = await connect();
const page = findPage(ctx, /customer-ruby-7292-dev-ed\.scratch\.lightning\.force\.com/);
if (!page) { console.log("NO_SF_PAGE"); process.exit(1); }
let _frame = null;
async function findFrame() {
  for (let i = 0; i < 24; i++) {
    for (const f of page.frames()) {
      if (f === page.mainFrame()) continue;
      const href = await Promise.race([f.evaluate(() => location.href).catch(() => ""), new Promise((r) => setTimeout(() => r(""), 1500))]);
      if (/surveytool\.dev\.veevart\.ai\/survey\//.test(href)) return f;
    }
    await page.waitForTimeout(250);
  }
  return null;
}
if (process.argv[2] !== "open") _frame = await findFrame();
const frame = () => _frame;
const log = (step, data) => { appendFileSync(new URL("./out/pasos.jsonl", import.meta.url), JSON.stringify({ t: new Date().toISOString(), step, ...data }) + "\n"); console.log(step, JSON.stringify(data)); };

async function iframeState() {
  const f = frame();
  if (!f) return { iframe: false };
  return f.evaluate(() => {
    const radios = [...document.querySelectorAll("input[type=radio]")];
    const groups = {};
    radios.forEach((r) => { (groups[r.name] ??= []).push(r); });
    const names = Object.keys(groups);
    const checked = (n) => { const g = groups[n] ?? []; const c = g.find((r) => r.checked); return c ? Number(c.value) : -1; };
    const ta = document.querySelector("textarea");
    const btn = [...document.querySelectorAll("button")].find((b) => /submit/i.test(b.textContent ?? ""));
    const alerts = [...document.querySelectorAll('[role=alert], [role=status], .survey-save-status')].map((e) => e.textContent.trim()).filter(Boolean);
    const keys = []; try { for (let i = 0; i < localStorage.length; i++) keys.push(localStorage.key(i)); } catch (e) { keys.push("ERR:" + e.name); }
    return { iframe: true, url: location.pathname, groups: names, principal: checked(names[0]), empresa: names[1] ? checked(names[1]) : null,
      texto: ta ? ta.value : null, submit: btn ? (btn.disabled ? "deshabilitado" : "habilitado") : "sin boton",
      avisos: alerts, gracias: /thank/i.test(document.body.innerText), tokensEnLocalStorage: keys.filter((k) => /draft/i.test(k)).length,
      clavesLocalStorage: keys.map((k) => k.replace(/[0-9a-f]{16,}/g, "<id>")) };
  });
}

const [action, arg] = process.argv.slice(2);
if (action === "open") {
  const res = await page.evaluate(async ({ SLUG, USER }) => {
    const base = "https://surveytool.dev.veevart.ai";
    const key = `veevart:surveyUsage:${SLUG}`;
    let usageCount = 1; try { usageCount = Number(localStorage.getItem(key) || "0") + 1; localStorage.setItem(key, String(usageCount)); } catch { /* igual que el LWC */ }
    const clientOrgId = window.location.hostname.split(".")[0] || "salesforce";
    const ctxBody = { clientOrgId, salesforceOrgId: "00DRt00000WkwJ0MAJ", respondentId: USER.id, respondentName: "User User",
      respondentEmail: "", respondentPhone: "", respondentTitle: "", userCreatedDate: USER.createdDate };
    const today = new Date().toISOString().slice(0, 10);
    const r = await fetch(`${base}/api/features/${encodeURIComponent(SLUG)}/surveys`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ featureSlug: SLUG, ...ctxBody, today, usageCount }) });
    const list = r.ok ? await r.json() : [];
    if (!list.length) return { eligStatus: r.status, eligible: [] };
    window.SURVEY_APP_URL = base;
    if (!window.SurveyWidget?.open) {
      await new Promise((ok, ko) => { const s = document.createElement("script"); s.src = "/resource/Auctifera__SurveyWidgetTrigger"; s.onload = ok; s.onerror = () => ko(new Error("script load failed")); document.head.appendChild(s); });
    }
    if (document.querySelector("[data-survey-widget='true']")) return { eligStatus: r.status, eligible: list.map((s) => s.id), skipped: "modal ya abierto" };
    window.SurveyWidget.open({ featureId: SLUG, surveyId: list[0].id, ...ctxBody, usageCount });
    try { localStorage.setItem(key, "0"); } catch { /* igual que el LWC */ }
    const imp = await fetch(`${base}/api/features/${encodeURIComponent(SLUG)}/impressions`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ surveyId: list[0].id, ...ctxBody, usageCount }) });
    return { eligStatus: r.status, eligible: list.map((s) => s.id), impression: imp.status, clientOrgId, usageCount };
  }, { SLUG, USER });
  await page.waitForTimeout(4000);
  _frame = await findFrame();
  log("open", { ...res, iframe: await iframeState() });
} else if (action === "state") {
  log("state " + (arg ?? ""), await iframeState());
} else if (action === "score" || action === "company") {
  const f = frame(); const st = await iframeState();
  const name = action === "score" ? st.groups[0] : st.groups[1];
  await f.locator(`input[type=radio][name="${name}"][value="${arg}"]`).check();
  await page.waitForTimeout(Number(process.env.WAIT ?? 2500));
  log(`${action} ${arg}`, await iframeState());
} else if (action === "reason") {
  const f = frame();
  await f.locator("textarea").first().fill(arg);
  await page.waitForTimeout(Number(process.env.WAIT ?? 2500));
  log(`reason`, await iframeState());
} else if (action === "close") {
  // Boton de cierre del modal del recurso estatico (en la pagina de Salesforce, fuera del iframe).
  const before = await iframeState();
  const closed = await page.evaluate(() => {
    const root = document.querySelector("[data-survey-widget='true']");
    const b = root && [...root.querySelectorAll("button")].find((x) => /close|×|✕/i.test((x.getAttribute("aria-label") ?? "") + x.textContent));
    if (b) { b.click(); return "boton"; }
    return root ? "sin boton" : "sin modal";
  });
  await page.waitForTimeout(2500);
  log("close", { via: closed, antes: before, modalAbierto: await page.evaluate(() => Boolean(document.querySelector("[data-survey-widget='true']"))) });
} else if (action === "submit") {
  const f = frame();
  await f.locator("button", { hasText: /submit/i }).first().click();
  await page.waitForTimeout(4000);
  log("submit", await iframeState());
} else if (action === "shot") {
  await page.bringToFront();
  log("shot", { file: await shot(page, arg) });
}
process.exit(0);
