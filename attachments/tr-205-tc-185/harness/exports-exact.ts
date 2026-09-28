// AC8 v2 · control del CSV por COLUMNA exacta (la v1 comparaba subcadenas y qa-tc185-r1 esta contenido en qa-tc185-r11).
import { createSessionCookie } from "../src/lib/auth.js";
import { store } from "../src/data/dynamodbStore.js";
const cookie = createSessionCookie({ sub: "qa-tc185-admin" }).split(";")[0];
const r = await fetch("http://localhost:4599/api/admin/responses/export.csv?from=2026-01-01&to=2026-12-31", { headers: { cookie } });
const text = await r.text();
const rows: string[][] = []; let row: string[] = [], cell = "", q = false;
for (let i = 0; i < text.length; i++) { const c = text[i];
  if (q) { if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; } else if (c === '"') q = false; else cell += c; }
  else if (c === '"') q = true; else if (c === ",") { row.push(cell); cell = ""; } else if (c === "\n") { row.push(cell.replace(/\r$/, "")); rows.push(row); row = []; cell = ""; } else cell += c; }
if (cell || row.length) { row.push(cell); rows.push(row); }
const h = rows[0]; const col = h.findIndex((x) => /respondent_id/i.test(x));
const enCsv = rows.slice(1).map((x) => x[col]).filter(Boolean).sort();
const conRespuesta = (await store.listResponses({})).map((x: any) => x.respondentId).filter(Boolean).sort();
console.log(JSON.stringify({ status: r.status, columna: h[col], encuestadosEnCsv: enCsv, encuestadosConRespuestaEnviada: conRespuesta,
  soloBorrador_r1: enCsv.includes("qa-tc185-r1"), soloBorrador_r5: enCsv.includes("qa-tc185-r5"), soloBorrador_r7: enCsv.includes("qa-tc185-r7"),
  csvIgualARespuestas: JSON.stringify(enCsv) === JSON.stringify(conRespuesta) }, null, 1));
