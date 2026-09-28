// b7-sin-respuesta · ejecutado en dev el 2026-09-28T23:02:37Z con el Playwright MCP.
async (page) => {
  const ctx = page.context(); const Q = ctx.__qa2; const mark = Q.events.length; Q.marks.b7 = mark;
  const F = 'fixtures/qa-tc182-ac5-404';
  let n = 0;
  await page.route('**/backups/*/upload-url', (route) => { if (route.request().method() === 'OPTIONS') return route.continue(); n++; return route.abort('connectionrefused'); });
  await page.route(/amazonaws\.com\/.*backup\.bak/, (route) => route.request().method() === 'PUT' ? route.abort('failed') : route.continue());
  await page.getByRole('button', { name: /upload new backup/i }).click();
  await page.getByPlaceholder('Enter Password').fill('<contrasena-sintetica>');
  await page.setInputFiles('#backup-file', F + '.bak');
  await page.setInputFiles('#cert-file', F + '.cer');
  await page.setInputFiles('#key-file', F + '.pvk');
  await page.getByRole('button', { name: /^create$/i }).click();
  await page.waitForTimeout(20000);
  await page.unroute('**/backups/*/upload-url'); await page.unroute(/amazonaws\.com\/.*backup\.bak/);
  const ev = Q.events.slice(mark).filter((e) => e.method !== 'GET');
  const st = await page.evaluate(async () => { const h={Authorization:'Bearer '+localStorage.getItem('migrationapp.access_token')}; const q=await (await fetch('<api-dev>/clients/<cliente-qa>/backups',{headers:h})).json(); return q.filter(b=>/db_7/.test(b.name)).map(b=>({n:b.name,s:b.status,u:b.uploadStatus,md:b.metadata})); });
  return { llamadasRefirmado: n, eventos: ev.map((e) => [e.t.slice(11, 19), e.dir, e.method, e.kind, e.path.replace(/^.*\/backups\//, '…/'), e.status ?? '', e.urlHash ?? '', e.signed ? JSON.stringify(e.signed) : '', e.body ?? '', e.error ?? ''].join(' | ')), st };
}
