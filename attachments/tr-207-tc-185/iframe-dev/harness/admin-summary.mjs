// Summary del admin acotado a la organizacion de nps_03 (Auctifera 3.0).
import { connect, findPage, shot, DEV } from "./lib.mjs";
import { appendFileSync } from "node:fs";
const { ctx } = await connect();
const page = findPage(ctx, /surveytool\.dev\.veevart\.ai/);
await page.goto(`${DEV}/admin/dashboard?tab=summary`, { waitUntil: "networkidle" }).catch(() => {});
await page.waitForTimeout(2000);
const orgSelect = page.locator("select").filter({ has: page.locator("option", { hasText: "Auctifera 3.0" }) }).first();
await orgSelect.selectOption({ label: "Auctifera 3.0 (00drt00000wkwj0maj)" });
await page.getByRole("button", { name: /^apply$/i }).click();
await page.waitForTimeout(3000);
const t = (await page.locator("body").innerText()).replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g, "<correo>");
const pick = (re) => (t.match(re) ?? [null])[0];
const out = { label: process.argv[3], scope: pick(/\d+ responses? in the selected scope|No responses[^\n]*/i), responses: pick(/RESPONSES\n\d+/), nps: pick(/NPS\n-?\d+|NPS\n-/), subjects: (t.split("SUBJECT\tRESPONSES\tNPS\tCSAT")[1] ?? "").split("Score distribution")[0].trim() };
appendFileSync(new URL("./out/summary.jsonl", import.meta.url), JSON.stringify({ t: new Date().toISOString(), ...out }) + "\n");
console.log(JSON.stringify(out, null, 1));
await shot(page, process.argv[2]);
process.exit(0);
