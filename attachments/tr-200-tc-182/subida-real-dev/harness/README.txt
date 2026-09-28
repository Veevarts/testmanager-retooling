HARNESS · subidas reales en dev · IM-1297 / TC-182 / TR-200 v2

Scripts tal como se ejecutaron en el Playwright MCP, en orden. Solo se sustituyen:
  <api-dev>               la URL base de la API de dev
  <cliente-qa>            el id del cliente "Test QA Backup"
  fixtures/               la ruta local de los ficheros sinteticos
  <contrasena-sintetica>  el valor escrito en el campo Password (los ficheros no estan cifrados)

Limitaciones del sandbox del MCP que explican la forma del codigo:
- no hay import() dinamico, asi que el hash es cyrb53 en JS y no sha256 de node:crypto;
- no existe el global URL, y por eso las URLs se parsean con una regex (el grabador v1 fallo por esto);
- globalThis no persiste entre llamadas; el estado vive en page.context().__qa2.

Los ficheros sinteticos se generan asi (el .bak con bytes aleatorios):
  head -c 441450496 /dev/urandom > fixtures/qa-tc182-ac1-largo.bak    # B3
  head -c 1048576   /dev/urandom > fixtures/qa-tc182-ac3-pequeno.bak  # B4
  echo 'QA TC-182 IM-1297 synthetic certificate placeholder. No real key material.' > *.cer  # 75 B
  echo 'QA TC-182 IM-1297 synthetic key placeholder. No real key material.' > *.pvk          # 67 B

Orden de ejecucion:
  01  grabador de red (contexto del navegador)
  02  B1 · refirmado 409 forzado                       (db_1)
  03  B2 · refirmado 404/500/404 forzado               (db_2)
  05  AC4 · cuatro llamadas al backend real
  04  B3 · subida larga, .bak sintetico, 110000 B/s    (db_3)
  06  quitar la limitacion + AC4 sobre db_3 en DONE (409)
  07  B4 · .bak de 1 MiB por PUT unico                 (db_4)
  08  B5 · subida larga del respaldo REAL de QA        (db_5)
  09  apagar la maquina del otro workspace al llegar a ON (intento de inspeccion, descartado)
  10  B6 · refirmado 400 forzado                       (db_6)
  11  B7 · refirmado sin respuesta                     (db_7)
  12  apagar db_5 desde su interruptor, tras llegar a ON
  <contrasena-sintetica-del-respaldo-real> es la contrasena con la que QA cifro la clave privada de
  su propio certificado (respaldo-real-qa/02-export.sql).
