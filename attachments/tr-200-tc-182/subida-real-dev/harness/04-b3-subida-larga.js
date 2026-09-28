// B3 / AC1-AC3: subida limitada a 110000 B/s con CDP para que el .bak de 441 MB dure mas que X-Amz-Expires=3600.
// Ejecutado con browser_run_code_unsafe / browser_evaluate del Playwright MCP, en dev, el 2026-09-28.
async (page) => {
  const ctx = page.context(); const Q = ctx.__qa2; const mark = Q.events.length; Q.marks.b3 = mark;
  const cdp = await ctx.newCDPSession(page); await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: 110000 });
  ctx.__qaCdp = cdp; Q.throttle = { uploadThroughput: 110000, desde: new Date().toISOString() };
  const F = 'fixtures/qa-tc182-ac1-largo';
  await page.getByRole('button', { name: /upload new backup/i }).click();
  await page.getByPlaceholder('Enter Password').fill('<contrasena-sintetica>');
  await page.setInputFiles('#backup-file', F + '.bak');
  await page.setInputFiles('#cert-file', F + '.cer');
  await page.setInputFiles('#key-file', F + '.pvk');
  Q.b3Start = new Date().toISOString();
  await page.getByRole('button', { name: /^create$/i }).click();
  await page.waitForTimeout(25000);
  return { inicio: Q.b3Start, eventos: Q.events.slice(mark).map((e) => [e.t.slice(11, 19), e.dir, e.method, e.kind, e.path.replace(/^.*\/backups\//, '…/'), e.status ?? '', e.partNumber ?? '', e.urlHash ?? '', e.expires ?? '', e.amzDate ?? '', e.signed ? JSON.stringify(e.signed) : '', e.len ?? '', e.error ?? ''].join(' | ')) };
}
