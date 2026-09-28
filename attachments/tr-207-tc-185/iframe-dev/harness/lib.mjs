// Driver del escenario 12 (TC-185): se conecta por CDP a la ventana de Chromium donde el usuario
// inicio sesion en el admin de Survey Tool dev. Nunca lee ni imprime cookies ni tokens.
const PW = process.env.PW;
const { chromium } = await import(PW);

export const DEV = "https://surveytool.dev.veevart.ai";
export const OUT = new URL("./out/", import.meta.url).pathname;

export async function connect() {
  const browser = await chromium.connectOverCDP("http://127.0.0.1:9333");
  const ctx = browser.contexts()[0];
  return { browser, ctx };
}

export function findPage(ctx, re) {
  return ctx.pages().find((p) => re.test(p.url()));
}

// Mascara: correos reales de @veevart.com y el correo sintetico del usuario de la scratch.
export async function mask(page) {
  const js = () => {
    const rx = /[A-Za-z0-9._%+-]+@(veevart\.com|example\.com)/g;
    const walk = (root) => {
      const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      let n; while ((n = w.nextNode())) { if (rx.test(n.nodeValue)) n.nodeValue = n.nodeValue.replace(rx, "<correo-oculto>"); }
      root.querySelectorAll?.("input").forEach((i) => { if (rx.test(i.value)) i.value = i.value.replace(rx, "<correo-oculto>"); });
    };
    walk(document.body);
    if (!window.__qaMask) { window.__qaMask = new MutationObserver(() => walk(document.body)); window.__qaMask.observe(document.body, { subtree: true, childList: true, characterData: true }); }
  };
  for (const f of page.frames()) { try { await f.evaluate(js); } catch { /* frame cross-origin sin acceso */ } }
}

export async function shot(page, name) {
  await mask(page);
  await page.waitForTimeout(300);
  await page.screenshot({ path: OUT + name, fullPage: false });
  return OUT + name;
}

// Llamada a la API de admin DENTRO de la pagina del admin (la cookie no sale del navegador).
export async function adminApi(page, method, path, body) {
  return page.evaluate(async ({ method, path, body }) => {
    const r = await fetch(path, { method, headers: body ? { "content-type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined, credentials: "include" });
    let data = null; try { data = await r.json(); } catch { /* no json */ }
    return { status: r.status, data };
  }, { method, path, body });
}
