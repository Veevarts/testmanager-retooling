TR-219 · IM-1202 · arnes de QA (no forma parte de los PRs)

qa-tc191.harness.spec.ts
  Se copia a src/data-migration/ de un clon de MigrationToolETL en main y se corre con
  `QA_OUT=<dir> fnm exec --using=22 npx jest src/data-migration/qa-tc191.harness.spec.ts`.
  Camino real del informe final: MigrationAppBackendModule (configuracion desde variables de entorno) ->
  MigrationAppBackendAdapter (fetch real) -> casos de uso de ficheros y estado -> RunMigrationUseCase.execute.
  Solo se sustituye runPipelineFlow (extraccion, CSV y subida). El backend es un servidor HTTP en 127.0.0.1 que
  responde como el endpoint de VPC (403 ForbiddenException), como API Gateway (200), 503 o sin responder, por ruta.
  H1 403 persistente (reintentos + ERROR undelivered) · H2 sin inventario -> FAILED · H3 inventario parcial ·
  H4 supresion por corrida sin tocar la llamada de estado · H5 plazo por intento · H6 clave y URL fuera de los logs ·
  H7 configuracion mal formada.

qa-tc191.harness.prefix.spec.ts
  Lo mismo sobre el padre de ETL #173 (e1d30d71): P1 403 persistente, P2 backend que no responde.

mutate-tc191.py <clon-etl> <clon-backend> <salida>
  Mutaciones E1-E7 (ETL) y B1-B4 (backend); cada una corre los specs del PR (y el arnes en el ETL) y restaura con
  git checkout.

salida.txt: resultados de H1-H7 y P1-P2 (clave falsa de QA, puerto efimero; ids sustituidos).
