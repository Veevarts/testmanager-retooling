// B1 / AC5: la ruta de refirmado responde 409 (forzado por QA). Corrio con el primer grabador (__qa1297), que no podia parsear URLs; la verificacion se hizo leyendo el respaldo en la API.
// Ejecutado con browser_run_code_unsafe / browser_evaluate del Playwright MCP, en dev, el 2026-09-28.
async (page) => {
  const F = 'fixtures/qa-tc182-ac5-409';
  const g = globalThis; const mark = g.__qa1297.events.length; g.__qa1297.marks = { ...(g.__qa1297.marks || {}), b1: mark };
  await page.route('**/backups/*/upload-url', (route) => route.request().method() === 'OPTIONS' ? route.continue() : route.fulfill({ status: 409, contentType: 'application/json', body: JSON.stringify({ statusCode: 409, message: 'QA TC-182: forced refusal (interceptado por QA)' }) }));
  await page.getByRole('button', { name: /upload new backup/i }).click();
  await page.getByPlaceholder('Enter Password').fill('<contrasena-sintetica>');
  await page.setInputFiles('#backup-file', F + '.bak');
  await page.setInputFiles('#cert-file', F + '.cer');
  await page.setInputFiles('#key-file', F + '.pvk');
  await page.getByRole('button', { name: /^create$/i }).click();
  await page.waitForTimeout(15000);
  await page.unroute('**/backups/*/upload-url');
  return g.__qa1297.events.slice(mark).map((e) => [e.t.slice(11, 19), e.dir, e.method, e.kind, e.path, e.status ?? '', e.partNumber ?? '', e.signed ? JSON.stringify(e.signed) : '', e.body ?? '', e.error ?? ''].join(' | '));
}
