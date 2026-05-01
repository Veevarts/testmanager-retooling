# TestManager Retooling

Repositorio base limpio para usar la extension TestManager sobre GitHub.

## Estructura

- `.testmanager.yml`: configuracion principal del proyecto
- `test-cases/`: casos de prueba
- `test-plans/`: planes de prueba
- `test-runs/`: ejecuciones de prueba
- `attachments/`: evidencias opcionales

Este repo se entrega en cero:

- sin artefactos ligados a issues previos
- sin ejecuciones historicas
- sin capturas de pantalla ni otros attachments

## Skills locales

Este repo expone tres skills locales para generar artefactos QA:

- `testcase-generator`
- `testplan-generator`
- `testrun-generator`

Estas skills viven en `.claude/skills/` y su comportamiento base esta definido en `.claude/CLAUDE.md`.

## Uso de skills con Codex

En este entorno, las skills no siempre aparecen con autocompletado al escribir `$`.
La forma recomendada de usarlas con Codex es mencionarlas explicitamente en el prompt.

Ejemplos:

- `usa testcase-generator para crear un caso de prueba de login`
- `usa testplan-generator para generar un plan de regresion para FR-981`
- `usa testrun-generator para crear una ejecucion para TC-4`

Tambien puedes invocarlas por intencion, sin nombrarlas:

- Si necesitas un `.testcase.yml`, Codex debe usar `testcase-generator`
- Si necesitas un `.testplan.yml`, Codex debe usar `testplan-generator`
- Si necesitas un `.testrun.yml`, Codex debe usar `testrun-generator`

Referencia:

- `.claude/CLAUDE.md` define el comportamiento del repo
- `.claude/skills/` mantiene las skills originales

## Flujo sugerido

1. Abre este repo en GitHub.
2. Abre la extension TestManager desde Brave.
3. Usa el side panel para buscar, editar y ejecutar casos.
4. Guarda cambios directamente sobre la rama actual.
