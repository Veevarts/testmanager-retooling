TR-216 · IM-1313 · harness de QA

mutate-be-tc189.py <clon-backend> <salida> <DATABASE_URL>
  Mutaciones B1-B8 sobre main. Por cada una corre `npx jest src/csm/tasks` y el banco SQL
  (`npm run csm-os:tasks:verify:local`) contra una base Postgres 16 + pgvector desechable y migrada desde main,
  y restaura con git checkout.
    docker exec <contenedor-pg> psql -U postgres -c 'CREATE DATABASE qa_tc189'
    DATABASE_URL=postgres://postgres:postgres@localhost:<puerto>/qa_tc189 npm run db:migrate:up

mutate-fe-tc189.py <clon-frontend> <salida>
  Mutaciones F1-F5 sobre main. Corre los 5 ficheros de tests del PR con Node 20 (fnm exec --using=20) y restaura.

Antes/despues: el banco de 846b7d70 contra un worktree de f96deb9f (TS_NODE_TRANSPILE_ONLY=true) y los tests de
d8a356c contra un worktree de 09830fc.

Dev: Playwright con la sesion del perfil, "View as" de la CSM de prueba, nombres enmascarados por addInitScript,
registro de peticiones no-GET, page.route abortando escrituras para ver su destino. Lecturas de la base de dev solo
con SELECT por Data API; logs de la Lambda de dev por CloudWatch.
