import { createRequire } from 'module';
const require = createRequire('/Users/veevart/Desktop/MigrationAppFrontend/package.json');
const { chromium } = require('playwright');
import fs from 'fs';
const BASE = 'https://surveytool.stg.veevart.ai';
const RID = process.env.RID;
const q = `clientOrgId=qa-tr218-org&respondentId=${RID}&respondentName=QA%20TR-218&respondentEmail=qa-tr218%40example.invalid`;
const url = `${BASE}/survey/fundraising?${q}`;
const out = { rid: RID, steps: [] };
const log = (k, v) => { out.steps.push({ k, v }); console.log(k, typeof v === 'string' ? v : JSON.stringify(v)); };
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await ctx.newPage();
const net = fs.createWriteStream('net-smoke.jsonl');
let lastResponsePost = null;
page.on('response', async r => {
  if (!r.url().includes('/api/')) return;
  let b = ''; try { b = await r.text(); } catch {}
  const rec = { t: new Date().toISOString(), m: r.request().method(), u: r.url().replace(BASE, ''), s: r.status(), req: r.request().postData()?.slice(0, 1500) ?? null, b: b.slice(0, 1500) };
  if (rec.m === 'POST' && rec.u === '/api/responses') lastResponsePost = { req: r.request().postData(), s: r.status(), b };
  net.write(JSON.stringify(rec) + '\n');
});
const waitDraft = (path) => page.waitForResponse(r => r.url().endsWith(path) && r.request().method() === 'POST', { timeout: 20000 });

// 1. Load + first meaningful answer -> draft created
await page.goto(url, { waitUntil: 'networkidle' });
const created = waitDraft('/api/survey-drafts');
await page.locator('input[name="nps"]').nth(9).check({ force: true });
const c = await created; const cb = await c.json().catch(() => ({}));
log('S1 draft create', { status: c.status(), keys: Object.keys(cb), status_field: cb.status, saveSequence: cb.saveSequence, answered: cb.answeredQuestionCount });
await page.getByText(/Saved/).first().waitFor({ timeout: 10000 }).catch(() => {});
log('S1 status text', (await page.locator('[role=status]').allTextContents()).join(' | '));
await page.screenshot({ path: 'shots/01-draft-saved.png', fullPage: true });

// 2. Reload same browser -> restore
const restored = waitDraft('/api/survey-drafts/restore');
await page.reload({ waitUntil: 'networkidle' });
const rs = await restored; const rb = await rs.json().catch(() => ({}));
log('S2 restore', { status: rs.status(), resumeCount: rb.resumeCount, saveSequence: rb.saveSequence, answered: rb.answeredQuestionCount });
log('S2 score 9 still checked', await page.locator('input[name="nps"]').nth(9).isChecked());
await page.screenshot({ path: 'shots/02-restored.png', fullPage: true });

// 3. Complete required fields
await page.locator('input[name="companyRecommend"]').nth(8).check({ force: true });
const tas = page.locator('textarea');
log('S3 textareas', await tas.count());
for (let i = 0; i < await tas.count(); i++) await tas.nth(i).fill(`QA TR-218 staging smoke ${i + 1}`);
await page.getByRole('button', { name: 'Paying pledges online' }).click();
await page.waitForTimeout(2500);
await page.screenshot({ path: 'shots/03-complete.png', fullPage: true });

// 4. Submit + observe button state during request
const submit = page.getByRole('button', { name: 'Submit' });
log('S4 submit enabled before', await submit.isEnabled());
const posted = page.waitForResponse(r => r.url().endsWith('/api/responses') && r.request().method() === 'POST', { timeout: 20000 });
await submit.click();
const disabledDuring = await submit.isDisabled().catch(() => 'n/a');
const pr = await posted; const pb = await pr.json().catch(() => ({}));
log('S4 submit', { status: pr.status(), responseId: pb.id ?? pb.responseId, disabledDuringRequest: disabledDuring });
await page.waitForTimeout(1500);
await page.screenshot({ path: 'shots/04-submitted.png', fullPage: true });
log('S4 page text', (await page.locator('body').innerText()).slice(0, 200).replace(/\s+/g, ' '));

// 5. Retry the exact same request (same draft token) -> same response, no duplicate
const retry = await page.request.post(`${BASE}/api/responses`, { data: JSON.parse(lastResponsePost.req), headers: { 'content-type': 'application/json' } });
const rtb = await retry.json().catch(() => ({}));
log('S5 retry same token', { status: retry.status(), responseId: rtb.id ?? rtb.responseId, sameAsFirst: (rtb.id ?? rtb.responseId) === (pb.id ?? pb.responseId) });
log('S5 draftToken present in submit body', Boolean(JSON.parse(lastResponsePost.req).draftToken));

// 6. Mobile layout of the public form (new respondent, load only)
const m = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true });
const mp = await m.newPage();
await mp.goto(`${BASE}/survey/fundraising?clientOrgId=qa-tr218-org&respondentId=${RID}-mobile`, { waitUntil: 'networkidle' });
const rows = await mp.locator('input[name="nps"]').evaluateAll(els => new Set(els.map(e => Math.round((e.closest('label')||e.parentElement).getBoundingClientRect().top))).size);
log('S6 mobile distinct score rows', rows);
await mp.screenshot({ path: 'shots/05-mobile.png', fullPage: true });
fs.writeFileSync('smoke-result.json', JSON.stringify(out, null, 1));
await browser.close();
