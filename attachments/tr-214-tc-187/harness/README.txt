Arnes de QA de TR-214 (IM-1245 v2). Nada de esto va al repo del producto. Reutiliza el de TR-210
(attachments/tr-210-tc-187/harness: fetch_rows.py y ui_vs_api.py sin cambios).

oracle.py <dir>          El oraculo de TR-210; solo salta tambien n16 (sin filtros, igual que c30).
qa-im1245-harness.spec.ts  El spec de TR-210 que ejecuta el WorkspaceService real con un repositorio falso.
antes-despues.sh         Lo corre en 1b8f067a (worktree, node_modules enlazado) y en a2ceb94b con los tres
                         conjuntos de filas y las 46 llamadas; mide aparte 1900..2026 y 0001..9999. Necesita
                         QA_SCRATCH. regresion/antes-vs-despues.txt.
mutate-v2.py <scratch>   Las 18 mutaciones + 2 BASE de scenario-0-unit-tests/mutaciones.txt.

La matriz de dev se pidio con fetch desde el navegador y el token de la sesion, que no sale del navegador. El
JSON crudo no se publica porque trae el id interno de la cuenta.
