ARNES DE QA · TC-185 · como se monto la ejecucion local (nada de esto toca ningun entorno)

1. DynamoDB Local en colima (amazon/dynamodb-local, en memoria, puerto 18765).
2. `cdk synth` del stack stateful de dev -> tablas con las MISMAS claves, GSI y proyecciones
   -> setup.mjs las crea.
3. seed.ts / seed-ui.ts siembran features y encuestas con el store REAL del servidor.
4. Servidor real: `npx tsx src/index.ts` con AWS_ENDPOINT_URL_DYNAMODB apuntando a DynamoDB Local,
   credenciales ficticias alfanumericas (DynamoDB Local 2.x rechaza guiones) y un
   AUTH_COOKIE_SECRET de pruebas que solo existe en esa ejecucion.
5. Sesion de admin: createSessionCookie() del propio servidor, firmada con ese secreto local.
   Pasa por el codigo real de autenticacion; no vale en ningun entorno.
6. Cliente real: Vite con una config aparte solo para cambiar puertos (3001 y 5173 los usaba
   otro proyecto) y apuntar el proxy al servidor local.
7. Navegador: Playwright 1.60 con Chromium headless (ui-flow*.mjs).
8. mutate.py: seis mutaciones sobre el clon, `npm test` como el CI, restauracion verificada por hash.
