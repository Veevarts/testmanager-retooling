// b5-respaldo-real-subida-larga · ejecutado en dev el 2026-09-28T21:46:39Z con el Playwright MCP.
async (page) => {
  const ctx = page.context(); const Q = ctx.__qa2; const mark = Q.events.length; Q.marks.b5 = mark;
  const cdp = await ctx.newCDPSession(page); await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: 110000 });
  ctx.__qaCdp5 = cdp; Q.throttle5 = { uploadThroughput: 110000, desde: new Date().toISOString() };
  const F = 'qa-backup/qa-tc182-real';
  await page.getByRole('button', { name: /upload new backup/i }).click();
  await page.getByPlaceholder('Enter Password').fill('<contrasena-sintetica-del-respaldo-real>');
  await page.setInputFiles('#backup-file', F + '.bak');
  await page.setInputFiles('#cert-file', F + '.cer');
  await page.setInputFiles('#key-file', F + '.pvk');
  Q.b5Start = new Date().toISOString();
  await page.getByRole('button', { name: /^create$/i }).click();
  await page.waitForTimeout(25000);
  return { inicio: Q.b5Start, eventos: Q.events.slice(mark).filter((e) => e.method !== 'GET').map((e) => [e.t.slice(11, 19), e.dir, e.method, e.kind, e.path.replace(/^.*\/backups\//, '…/'), e.status ?? '', e.partNumber ?? '', e.urlHash ?? '', e.amzDate ?? '', e.signed ? JSON.stringify(e.signed) : '', e.error ?? ''].join(' | ')) };
}
