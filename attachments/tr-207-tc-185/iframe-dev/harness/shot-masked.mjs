// Captura del widget en Salesforce tapando el mensaje de error (contiene identificadores internos de AWS).
import { connect, findPage, mask, OUT } from "./lib.mjs";
const { ctx } = await connect();
const page = findPage(ctx, /customer-ruby-7292/);
await page.bringToFront(); await mask(page);
let f = null;
for (const fr of page.frames()) { if (fr === page.mainFrame()) continue; const h = await fr.evaluate(() => location.href).catch(() => ""); if (/surveytool\.dev/.test(h)) f = fr; }
const info = await f.evaluate(() => { const els = [...document.querySelectorAll("body *")].filter((e) => e.children.length === 0 && /AccessDenied/.test(e.textContent)); return els.map((e) => ({ tag: e.tagName, role: e.getAttribute("role"), cls: e.className })); });
console.log(JSON.stringify(info));
await f.evaluate(() => document.querySelectorAll("[role=alert]").forEach((e) => { e.style.overflow = "hidden"; e.style.overflowWrap = "anywhere"; }));
const err = f.locator("[role=alert]");
console.log("count", await err.count());
await page.screenshot({ path: OUT + process.argv[2], mask: [err], maskColor: "#d33" });
process.exit(0);
