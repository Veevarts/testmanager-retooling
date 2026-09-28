// B2 / AC5: refirmado 404, 500, 404 -> el frontend cae al enlace de creacion. QA corta el PUT del .bak para que db_2 no aprovisione.
// Ejecutado con browser_run_code_unsafe / browser_evaluate del Playwright MCP, en dev, el 2026-09-28.
async (page) => {
  const ctx = page.context(); const Q = ctx.__qa2; const mark = Q.events.length; Q.marks.b2 = mark;
  const F = 'fixtures/qa-tc182-ac5-404';
  let n = 0; const plan = [404, 500, 404];
  await page.route('**/backups/*/upload-url', (route) => { if (route.request().method() === 'OPTIONS') return route.continue(); const st = plan[n++] ?? 404;
    return route.fulfill({ status: st, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify({ statusCode: st, message: `QA TC-182: forced ${st} (interceptado por QA)` }) }); });
  await page.route(/amazonaws\.com\/.*backup\.bak/, (route) => route.request().method() === 'PUT' ? route.abort('failed') : route.continue());
  await page.getByRole('button', { name: /upload new backup/i }).click();
  await page.getByPlaceholder('Enter Password').fill('<contrasena-sintetica>');
  await page.setInputFiles('#backup-file', F + '.bak');
  await page.setInputFiles('#cert-file', F + '.cer');
  await page.setInputFiles('#key-file', F + '.pvk');
  await page.getByRole('button', { name: /^create$/i }).click();
  await page.waitForTimeout(20000);
  await page.unroute('**/backups/*/upload-url'); await page.unroute(/amazonaws\.com\/.*backup\.bak/);
  return { llamadasRefirmado: n, eventos: Q.events.slice(mark).map((e) => [e.t.slice(11, 19), e.dir, e.method, e.kind, e.path.replace(/^.*\/backups\//, '…/'), e.status ?? '', e.urlHash ?? '', e.expires ?? '', e.signed ? JSON.stringify(e.signed) : '', e.body ?? '', e.error ?? ''].join(' | ')) };
}
