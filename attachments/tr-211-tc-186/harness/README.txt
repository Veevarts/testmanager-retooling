Arnes de QA de TR-211 (IM-1207 v4). Nada de esto va al repo del producto.

dq.py "<SELECT ...>"   Consultas de SOLO LECTURA a la base de dev via RDS Data API (rechaza cualquier
                       sentencia que no sea SELECT/WITH). Toma el ARN del generador del autor, que solo
                       admite dev; no contiene ARNs ni credenciales.
disp.sh <etiqueta> <accountId>
                       Despacha account.renewal_window_entered (days=90) al generador local
                       (localhost:4311), que corre el pipeline completo contra dev.
mutate-v3.py           Las 9 mutaciones + BASE de scenario-0-unit-tests/mutaciones.txt. Necesita
                       QA_PG_URL (Postgres local) y una plantilla csmos_tpl migrada hasta 0088.
