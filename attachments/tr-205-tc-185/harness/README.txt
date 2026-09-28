ARNES DE QA · TC-185 v2 / TR-205 · mismo montaje que TR-202 (attachments/tr-202-tc-185/harness)
DynamoDB Local en colima con las tablas del stack sintetizado, servidor real, cliente real (Vite
en puertos aparte), Chromium headless; sesion de admin firmada con un secreto local que no vale en
ningun entorno. Base limpia y una sola corrida, en este orden:

1. setup.mjs + seed.ts (de TR-202)
2. api-scenarios-v2.ts   escenarios de API de TR-202 + SEGUNDO_NAVEGADOR con el contrato nuevo,
                         AC6 con borrador, AC9_TERCERO y CONCURRENCIA (20 + 20 carreras)
3. seed-ui.ts (de TR-202)
4. ui-flow-regresion.mjs recorrido principal de TR-202 (capturas 01-08 y 14) sin su seccion de
                         segundo navegador, que sustituye:
5. ui-flow-v2.mjs        segundo navegador en pagina directa y widget; navegador desplazado;
                         lo escrito con el aviso visible (capturas v2-01..v2-16)
6. ui-flow-ac4.mjs       cambio real de definicion (captura 13). Va el ultimo porque cambia la
                         encuesta que usan los demas recorridos.
7. exports-exact.ts      control del CSV por la columna respondent_id exacta
