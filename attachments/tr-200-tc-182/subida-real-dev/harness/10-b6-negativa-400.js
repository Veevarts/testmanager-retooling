// b6-negativa-400 · ejecutado en dev el 2026-09-28T22:57:03Z con el Playwright MCP.
async (page) => {
  const ctx = page.context(); const Q = ctx.__qa2; const mark = Q.events.length; Q.marks.b6 = mark;
  const F = 'fixtures/qa-tc182-ac5-409';
  let n = 0;
  await page.route('**/backups/*/upload-url', (route) => { if (route.request().method() === 'OPTIONS') return route.continue(); n++; return route.fulfill({ status: 400, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify({ statusCode: 400, message: 'QA TC-182: forced 400 (interceptado por QA)', error: 'Bad Request' }) }); });
  await page.getByRole('button', { name: /upload new backup/i }).click();
  await page.getByPlaceholder('Enter Password').fill('<contrasena-sintetica>');
  await page.setInputFiles('#backup-file', F + '.bak');
  await page.setInputFiles('#cert-file', F + '.cer');
  await page.setInputFiles('#key-file', F + '.pvk');
  await page.getByRole('button', { name: /^create$/i }).click();
  await page.waitForTimeout(15000);
  await page.unroute('**/backups/*/upload-url');
  const ev = Q.events.slice(mark).filter((e) => e.method !== 'GET');
  const st = await page.evaluate(async () => { const h={Authorization:'Bearer '+localStorage.getItem('migrationapp.access_token')}; const q=await (await fetch('<api-dev>/clients/<cliente-qa>/backups',{headers:h})).json(); return q.filter(b=>/db_6/.test(b.name)).map(b=>({n:b.name,s:b.status,u:b.uploadStatus,md:b.metadata})); });
  return { llamadasRefirmado: n, putsS3: ev.filter(e => e.kind === 's3' && e.dir === 'req').length, eventos: ev.map((e) => [e.t.slice(11, 19), e.dir, e.method, e.kind, e.path.replace(/^.*\/backups\//, '…/'), e.status ?? '', e.urlHash ?? '', e.body ?? '', e.error ?? ''].join(' | ')), st };
}
