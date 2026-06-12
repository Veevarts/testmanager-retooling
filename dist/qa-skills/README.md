# QA Skills · Veevart

Bundle con las 2 skills de QA que ya están en producción:

| Skill | Rol | Qué hace |
|---|---|---|
| `/qa-bundle-generator` | El Planeador | Lee una historia de Jira y arma el plan QA (en la sub-tarea de Jira) + el `.testcase.yml` en el repo. |
| `/qa-test-executor` | El Ejecutor | Toma el plan, corre el PR pre-fix vs post-fix, regresión técnica + OWASP Top 10, y escribe el `.testrun.yml` con evidencia. |

Las dos se combinan: `historia Jira → /qa-bundle-generator → /qa-test-executor → defectos en Jira con evidencia`.

## Instalación

### Opción 1 — Instalar en un proyecto específico (recomendado)

```bash
# desde la raíz del proyecto destino
mkdir -p .claude/skills
cp -r qa-bundle-generator .claude/skills/
cp -r qa-test-executor .claude/skills/
```

Las skills quedan versionadas con el repo y disponibles solo para ese proyecto.

### Opción 2 — Instalar global (todos tus proyectos)

```bash
mkdir -p ~/.claude/skills
cp -r qa-bundle-generator ~/.claude/skills/
cp -r qa-test-executor ~/.claude/skills/
```

### Opción 3 — Instalador automático

```bash
./install.sh           # instala global (~/.claude/skills/)
./install.sh --project # instala en el proyecto actual (.claude/skills/)
```

## Cómo invocarlas

Una vez instaladas, en Claude Code escribes:

```
/qa-bundle-generator IM-707
```

```
/qa-test-executor TC-54
```

## Prerrequisitos del proyecto destino

Para que las skills funcionen el repo destino necesita:

- **Atlassian MCP** configurado (las skills crean / editan issues de Jira).
- **GitHub CLI (`gh`)** autenticado (para leer PRs).
- Estructura tipo TestManager con `test-cases/`, `test-runs/`, `.testmanager.yml` — si no existe, las skills la crean.

Si el proyecto destino aún no la tiene, las skills proponen la estructura mínima en la primera ejecución.

## Compatibilidad

- Probado con: Claude Code (CLI, VSCode extension, desktop app).
- No requiere internet más allá del MCP y `gh`.
- No ejecuta nada destructivo sin confirmación explícita.

## Versión

Snapshot exportado del workspace `testmanager-retooling` · 12 jun 2026.
