// Grabador de red instalado en el contexto del navegador. Guarda metodo, ruta abreviada, codigo y, de cada URL firmada, solo su hash cyrb53, X-Amz-Expires y X-Amz-Date. Nunca la URL.
// Ejecutado con browser_run_code_unsafe / browser_evaluate del Playwright MCP, en dev, el 2026-09-28.
async (page) => {
  const ctx = page.context();
  if (ctx.__qa2) return { ya: true, n: ctx.__qa2.events.length };
  const H = (str, seed = 7) => { let h1 = 0xdeadbeef ^ seed, h2 = 0x41c6ce57 ^ seed; for (let i = 0; i < str.length; i++) { const ch = str.charCodeAt(i); h1 = Math.imul(h1 ^ ch, 2654435761); h2 = Math.imul(h2 ^ ch, 1597334677); } h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909); h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909); return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16).padStart(14, '0'); };
  const Q = ctx.__qa2 = { events: [], installed: new Date().toISOString(), marks: {} };
  const shortId = (s) => s.replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g, (m) => m.slice(0, 8));
  const parse = (u) => { const m = /^https?:\/\/([^\/?#]+)([^?#]*)(?:\?([^#]*))?/.exec(u) || []; const host = m[1] || ''; const path = m[2] || ''; const qs = {}; (m[3] || '').split('&').forEach((kv) => { const i = kv.indexOf('='); if (i > 0) qs[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(kv.slice(i + 1)); }); return { host, path, qs }; };
  const scrub = (u) => { const { host, path, qs } = parse(u); const api = /execute-api/.test(host); const s3 = !api && /amazonaws\.com$/.test(host);
    return { kind: s3 ? 's3' : (api ? 'api' : 'other'), path: api ? shortId(path.replace(/^\/dev\/api/, '')) : shortId(path), expires: qs['X-Amz-Expires'] || null, amzDate: qs['X-Amz-Date'] || null, partNumber: qs['partNumber'] || null, urlHash: s3 ? H(u) : undefined }; };
  const interesting = (u) => (/execute-api/.test(u) && /backups/.test(u)) || (/amazonaws\.com/.test(u) && !/execute-api/.test(u));
  const onReq = (r) => { const u = r.url(); if (!interesting(u) || r.method() === 'OPTIONS') return; Q.events.push({ t: new Date().toISOString(), dir: 'req', method: r.method(), ...scrub(u), len: r.headers()['content-length'] || null }); };
  const onRes = async (r) => { const u = r.url(); if (!interesting(u) || r.request().method() === 'OPTIONS') return; const s = scrub(u);
    const ev = { t: new Date().toISOString(), dir: 'res', method: r.request().method(), status: r.status(), ...s };
    if (s.kind === 'api' && /upload-link|upload-url|sign-part|multipart\/init/.test(s.path)) {
      try { const j = await r.json(); const walk = (o, pfx = '') => { const out = {}; if (!o || typeof o !== 'object') return out;
          for (const [k, v] of Object.entries(o)) { if (typeof v === 'string' && /^https:\/\/.*X-Amz-/.test(v)) { const p = parse(v); out[pfx + k] = { urlHash: H(v), expires: p.qs['X-Amz-Expires'], amzDate: p.qs['X-Amz-Date'] }; }
            else if (v && typeof v === 'object') Object.assign(out, walk(v, pfx + k + '.')); } return out; };
        ev.signed = walk(j); if (j && j.backupId) ev.backupId = String(j.backupId).slice(0, 8); } catch (e) { ev.bodyErr = String(e).slice(0, 80); } }
    if (s.kind === 'api' && r.status() >= 400) { try { ev.body = (await r.text()).slice(0, 200); } catch {} }
    Q.events.push(ev); };
  const onFail = (r) => { const u = r.url(); if (!interesting(u)) return; Q.events.push({ t: new Date().toISOString(), dir: 'failed', method: r.method(), ...scrub(u), error: r.failure()?.errorText }); };
  ctx.on('request', onReq); ctx.on('response', onRes); ctx.on('requestfailed', onFail);
  Q.off = () => { ctx.off('request', onReq); ctx.off('response', onRes); ctx.off('requestfailed', onFail); };
  return { ok: true, prueba: scrub('<api-dev>/clients/<cliente-qa>/backups/x/upload-url') };
}
