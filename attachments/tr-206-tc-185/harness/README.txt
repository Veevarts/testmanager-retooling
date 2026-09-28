ARNES · TC-185 v3 / TR-206 · mismo montaje que TR-202 y TR-205 (ver sus carpetas harness/).
Orden de la corrida (base limpia): setup + seed -> api-scenarios-v2.ts (sin cambios; salida
renombrada a api-scenarios-v3.json) -> seed-ui -> ui-flow-regresion.mjs -> ui-flow-v2.mjs (mismos
pasos que TR-205, para comparar N1/N2) -> ui-flow-v3.mjs (caminos nuevos; su bloque D cambia la
definicion y va al final) -> ui-flow-ac4.mjs -> exports-exact.ts y metrics.ts.
mutate-v3.py: mutaciones M1, M4, M9, M11-M14 con npm test como el CI; restaura con git checkout.
