// Admin de Survey Tool DEV por la UI: node admin.mjs <tab> <captura> [clic-en-fila]
import { connect, findPage, shot, DEV } from "./lib.mjs";
import { appendFileSync } from "node:fs";
const [tab, file, clickRow] = process.argv.slice(2);
const { ctx } = await connect();
const page = findPage(ctx, /surveytool\.dev\.veevart\.ai/);
await page.bringToFront();
await page.goto(`${DEV}/admin/dashboard?tab=${tab}`, { waitUntil: "networkidle" }).catch(() => {});
await page.waitForTimeout(2500);
let rowText = null;
if (clickRow) {
  const row = page.getByText(/QA TC-185 Iframe/).first();
  if (await row.count()) { rowText = (await row.textContent())?.slice(0, 120); await row.click(); await page.waitForTimeout(2000); }
}
const text = (await page.locator("main").innerText().catch(() => page.locator("body").innerText())).replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g, "<correo>");
const lines = text.split("\n").filter((l) => /QA TC-185|005Rt00000aTMIrIAO|00drt00000wkwj0maj|customer-ruby|Responded|NPS|In progress|Answered|answered|unanswered|Unanswered/i.test(l)).slice(0, 40);
appendFileSync(new URL("./out/admin.jsonl", import.meta.url), JSON.stringify({ t: new Date().toISOString(), tab, file, rowText, lines }) + "\n");
console.log(JSON.stringify({ tab, rowText, lines }, null, 1));
await shot(page, file);
process.exit(0);
