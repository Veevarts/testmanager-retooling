// B4 / AC3: .bak de 1 MiB por PUT unico; QA corta el /complete para que db_4 no aprovisione.
// Ejecutado con browser_run_code_unsafe / browser_evaluate del Playwright MCP, en dev, el 2026-09-28.
async (page) => {
  const ctx = page.context(); const Q = ctx.__qa2; const mark = Q.events.length; Q.marks.b4 = mark;
  const F = 'fixtures/qa-tc182-ac3-pequeno';
  await page.route(/\/backups\/[0-9a-f-]+\/complete$/, (route) => route.request().method() === 'POST' ? route.abort('failed') : route.continue());
  await page.getByRole('button', { name: /upload new backup/i }).click();
  await page.getByPlaceholder('Enter Password').fill('<contrasena-sintetica>');
  await page.setInputFiles('#backup-file', F + '.bak');
  await page.setInputFiles('#cert-file', F + '.cer');
  await page.setInputFiles('#key-file', F + '.pvk');
  await page.getByRole('button', { name: /^create$/i }).click();
  await page.waitForTimeout(20000);
  await page.unroute(/\/backups\/[0-9a-f-]+\/complete$/);
  return Q.events.slice(mark).filter((e) => !(e.method === 'GET' && /\/backups$/.test(e.path))).map((e) => [e.t.slice(11, 19), e.dir, e.method, e.kind, e.path.replace(/^.*\/backups\//, '…/'), e.status ?? '', e.urlHash ?? '', e.signed ? JSON.stringify(e.signed) : '', e.body ?? '', e.error ?? ''].join(' | '));
}
