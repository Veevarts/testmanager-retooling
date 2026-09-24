/**
 * Esta la ruta de refirmado VIVA en el entorno de pruebas?
 *
 * Mismo metodo que scripts/probe-api-routes.mjs del propio frontend: SIN TOKEN.
 * Una ruta que existe contesta 401 (el guard de Cognito corrio). Una que no
 * existe contesta 404 (el router nunca la emparejo). No hace falta credencial
 * y no se escribe nada.
 *
 * SOLO dev. Produccion no se toca: si el arreglo esta en prod ya lo responde
 * git -- no esta en la rama `stable` -- sin una sola peticion.
 *
 * El control negativo es obligatorio: si una ruta inventada tambien diera 401,
 * el 401 no probaria nada.
 */
const ID = "00000000-0000-0000-0000-000000000001";
const BASE = "<api-de-pruebas>";
const PATHS = [
  ["POST", `/clients/${ID}/backups/${ID}/upload-url`,           "LA RUTA NUEVA (IM-1297)"],
  ["POST", `/clients/${ID}/backups/${ID}/multipart/sign-part`,  "control: hermana que ya existia"],
  ["POST", `/clients/${ID}/backups/upload-link`,                "control: la ruta de creacion"],
  ["POST", `/clients/${ID}/backups/${ID}/upload-url-inventada`, "CONTROL NEGATIVO: no existe"],
];

console.log(`=== dev (rama main) — ${BASE} ===`);
for (const [method, path, label] of PATHS) {
  let status;
  try {
    const res = await fetch(BASE + path, {
      method,
      headers: { "content-type": "application/json" },
      body: "{}",
      signal: AbortSignal.timeout(15000),
    });
    status = res.status;
  } catch (e) { status = `ERR ${e.message}`; }
  const verdict = status === 401 ? "la ruta EXISTE"
                : status === 404 ? "*** NO SERVIDA ***"
                : `(${status})`;
  console.log(`  ${String(status).padEnd(5)} ${method.padEnd(5)} ${path.padEnd(74)} ${verdict}   ${label}`);
}
