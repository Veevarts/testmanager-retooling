TR-221 · IM-1202 · arnes de QA v2 (no forma parte de los PRs)

qa-tc191-v2.harness.spec.ts
  Se copia a src/data-migration/ de un clon de MigrationToolETL en main y se corre con
  `QA_OUT=<dir> fnm exec --using=22 npx jest --forceExit src/data-migration/qa-tc191-v2.harness.spec.ts`.
  Adaptador real (configuracion desde variables de entorno, fetch real) y la clase RunHeartbeat real de #190 contra un
  servidor HTTP en 127.0.0.1. A1 403 persistente con reintentos · HB1 latidos con progreso y parada al estancarse ·
  HB2 un latido rechazado es un solo intento · H5 plazo por intento · H6 clave y URL fuera de los logs (estado, ficheros
  y latido) · H7 configuracion mal formada. El flujo de la corrida (aislamiento, aviso por objeto) lo cubren los specs
  de #190 y las corridas de dev.

mutate-tc191-v2.py <clon-etl> <clon-backend> <salida>
  Mutaciones X1-X5 (ETL) e Y1-Y6 (backend) contra los specs de los PRs; restaura con git checkout.

salida.txt: resultados del arnes (clave falsa de QA, puerto efimero, ids sustituidos).
