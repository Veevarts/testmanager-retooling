// Registrador de red: peticiones a la API de Survey Tool dev hechas desde Salesforce (pagina e iframe).
// Nunca guarda tokens: solo metodo, ruta sin query, codigo y campos no sensibles.
import { connect } from "./lib.mjs";
import { appendFileSync } from "node:fs";
const SAFE = ["score", "companyRecommendScore", "saveSequence", "replaceExistingDraft", "currentStep", "answeredQuestionCount", "code", "status", "error", "surveyId", "resumeCount", "clientOrgId", "salesforceOrgId"];
const pick = (o) => { if (!o || typeof o !== "object") return null; const r = {}; for (const k of SAFE) if (k in o) r[k] = o[k]; if ("comment" in o) r.commentLen = o.comment == null ? null : String(o.comment).length; if ("draftToken" in o) r.draftToken = o.draftToken ? "<presente>" : o.draftToken; if ("keepalive" in o) r.keepalive = o.keepalive; r.keys = Object.keys(o).filter((k) => k !== "draftToken"); return r; };
const { ctx } = await connect();
ctx.on("request", (req) => {
  const u = req.url(); if (!/surveytool\.dev\.veevart\.ai\/api\//.test(u) || /\/api\/admin\//.test(u)) return;
  let body = null; try { body = pick(JSON.parse(req.postData() ?? "null")); } catch { body = req.postData() ? "<no-json>" : null; }
  req.__t = Date.now();
  appendFileSync(new URL("./out/net.jsonl", import.meta.url), JSON.stringify({ t: new Date().toISOString(), ev: "req", method: req.method(), path: u.replace(/^https:\/\/[^/]+/, "").replace(/\?.*$/, ""), frame: (() => { try { return new URL(req.frame().url()).host; } catch { return "?"; } })(), body }) + "\n");
});
ctx.on("response", async (res) => {
  const u = res.url(); if (!/surveytool\.dev\.veevart\.ai\/api\//.test(u) || /\/api\/admin\//.test(u)) return;
  let body = null; try { const j = await res.json(); body = Array.isArray(j) ? { array: j.length, ids: j.map((x) => x.id) } : pick(j); } catch { body = null; }
  appendFileSync(new URL("./out/net.jsonl", import.meta.url), JSON.stringify({ t: new Date().toISOString(), ev: "res", method: res.request().method(), path: u.replace(/^https:\/\/[^/]+/, "").replace(/\?.*$/, ""), status: res.status(), body }) + "\n");
});
setInterval(() => {}, 1 << 30);
