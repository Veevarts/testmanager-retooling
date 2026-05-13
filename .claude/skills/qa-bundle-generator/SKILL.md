# QA Bundle Generator

Generate the full QA bundle for a Jira implementation story: write a complete QA test plan into the Jira QA Sub-task description AND create the matching `.testcase.yml` file in the repo, in a single coordinated workflow.

Agent identity for this skill: `codex` - direct, technical, concise, and QA-focused.

This skill wraps `testcase-generator` and adds the Jira side. It does NOT generate `.testplan.yml` files. Use `testplan-generator` for those.

## Trigger

When the user asks to:

- Build the full QA coverage for a Jira story.
- Produce a QA test plan in Jira AND a test case file in the repo from the same story.
- Mentions "qa-bundle", "/qa-bundle", "armar plan QA completo", "plan QA y test case", "cobertura QA completa de la historia", or similar phrasing that bundles Jira description + repo artifact.

Do NOT trigger this skill when the user only wants one side (only Jira description, or only `.testcase.yml`). Use `testcase-generator` for the latter and write Jira manually for the former.

## Inputs

Accepts either:

- A parent story key (e.g., `IM-707`) - the skill resolves or creates the QA Sub-task.
- A QA Sub-task key (e.g., `IM-725`) - the skill resolves the parent story automatically.

If the input is ambiguous (typed without project key), ask once.

## Outputs

1. Jira QA Sub-task description updated with the full QA test plan (Spanish framing + English gherkin scenarios), mirror of the IM-687 / IM-725 pattern.
2. `.testcase.yml` file written under `test-cases/<PARENT-KEY>/<PARENT-KEY>-TC-<NN>-<slug>.testcase.yml`.
3. Console summary with the Jira URL, the file path, and any open risks flagged.

This skill DOES NOT commit or push. The user decides when to push.

## Workflow

1. Read the current project's `.claude/CLAUDE.md` (if present) and `.claude/skills/testcase-generator/SKILL.md` for repo rules and `.testcase.yml` schema. The skill assumes a TestManager-style repo with `test-cases/`, `.testmanager.yml`, and the standard testcase-generator conventions.
2. Resolve Atlassian cloudId via `mcp__atlassian__getAccessibleAtlassianResources` (or pass site hostname directly to other tools first).
3. Fetch the input issue with `mcp__atlassian__getJiraIssue` (responseContentFormat: `markdown`).
   - If the input is a QA Sub-task, also fetch its parent.
   - If the input is a story, list its subtasks and find one with `issuetype.name = "QA Sub-task"` (id `10595`).
4. If no QA Sub-task exists for the parent story, create it with `mcp__atlassian__createJiraIssue`:
   - `project.key` = parent project key.
   - `issuetype.name` = `QA Sub-task`.
   - `parent.key` = parent story key.
   - `summary` = `QA Review`.
   - `assignee.accountId` = current user (`mcp__atlassian__atlassianUserInfo`).
   - Capture the new sub-task key.
5. If the parent story status is `Rechazado` or otherwise closed-as-rejected, flag it once and confirm with the user before continuing (do not silently generate QA artifacts for a permanently rejected story).
6. Extract coverage signals from the parent story description and ACs:
   - Gherkin or freeform Acceptance Criteria.
   - Concrete examples (accounts, IDs, dates, amounts, opportunities).
   - Repositories in scope, target system gaps marked TBD.
   - Edge cases documented as missing (look for "Missing", "TBD", "Risk", "Edge case" sections).
   - Related issuelinks (regression candidates, dependencies).
7. Build the scenario set:
   - 1 scenario per AC (mapped tag `ac-<n>`).
   - 1 scenario per concrete example in the description (tag `regression-evidence` or the customer/account name).
   - 1 scenario per documented missing or TBD edge case (tag `missing-doc` or `edge-case`).
   - 1 negative scenario for the obvious empty/no-op case if applicable.
8. Scan `test-cases/**` to determine the next sequential `TC-<NN>` key. NEVER duplicate keys.
9. Write the `.testcase.yml`:
   - Path: `test-cases/<PARENT-KEY>/<PARENT-KEY>-TC-<NN>-<feature-slug>.testcase.yml`.
   - Apply all `testcase-generator` rules (UUID v4, gherkin format, lowercase hyphenated tags, `codex` as author, ISO-8601 timestamps).
   - Tags MUST include: parent story key (lowercase), epic key if present, QA sub-task key (lowercase), and the functional area.
   - Description MUST mention the parent story key, the QA sub-task key, the epic, and any open risks (TBD targets, rejected status, missing edge case mappings).
10. Build the Jira QA Sub-task description in the structured format below and write it with `mcp__atlassian__editJiraIssue` (contentFormat: `markdown`).
11. Summarize the result in one short message: Jira URL, file path, scenario count, flagged risks.

## Jira QA Sub-task Description Format

Sections in this exact order (Spanish framing + English gherkin blocks):

```
## Plan de pruebas QA

Sub-task QA para validar <PARENT-KEY> (<parent summary>), bajo el epic
<EPIC-KEY> <epic summary>. <1-2 sentence summary of what is validated>.

## Objetivo

Validar que <feature/pipeline/migration>:
* <bullet 1>,
* <bullet 2>,
* ...

## Alcance funcional

Se va a probar:
* <area 1>,
* <area 2>,
* ...

## Precondiciones

* <precondition 1>
* <precondition 2>
* ...

## Escenarios funcionales

### Scenario 1 - <Behavior described in plain English>

```gherkin
Scenario: <Same title as the heading>
  Given <context>
  When <action>
  Then <observable outcome>
  And <secondary outcome>
```

### Scenario 2 - <...>

```gherkin
...
```

## Riesgos abiertos del ticket

* <risk 1, e.g. SF target object TBD>
* <risk 2, e.g. edge cases missing from spec>
* <risk 3, e.g. parent is Rechazado>

## Criterios de salida QA

* <exit condition 1>
* <exit condition 2>
* ...

## Test case asociado

* <TC-NN> - <relative repo path>
```

Headings use `##` and `###`. Gherkin blocks use triple-backtick `gherkin` fences. Do not use the legacy Jira `h2.` syntax - the Atlassian MCP renders markdown directly.

## Rules

1. **One QA Sub-task per parent story**. If multiple QA Sub-tasks exist, ask which one to update.
2. **One `.testcase.yml` per parent story** unless the user explicitly asks to split the coverage. Group scenarios in a single file the same way `testcase-generator` does.
3. **Mirror, do not invent**. Every scenario must trace back to an AC, a concrete example in the description, a documented missing edge case, or an explicit risk note. Do not invent scenarios for features the story does not describe.
4. **Flag risks, do not hide them**. If the parent story has TBD targets, missing edge cases, or is in a rejected state, surface those in the `## Riesgos abiertos del ticket` section AND in the `.testcase.yml` description. Do not pretend they are resolved.
5. **Spanish framing, English gherkin**. Section titles, bullets and risk notes in Spanish. Gherkin steps in English. This matches the IM-687 / IM-725 baseline and keeps automation-friendly scenarios.
6. **Author and metadata defaults**. `metadata.createdBy = "codex"`. `version = 1`. ISO-8601 timestamps reflecting the current generation time.
7. **No `.testplan.yml`**. This skill does not produce TestManager test plan files. If the user also wants `.testplan.yml`, run `testplan-generator` afterwards.
8. **No commit, no push**. Leave the working tree dirty for the user to review.
9. **Sub-task creation safety**. Only create a QA Sub-task when none exists. Never create a second one. Never reassign an existing QA Sub-task.
10. **cloudId resolution**. Use the site hostname (e.g., `veevart.atlassian.net`) as `cloudId` first; fall back to `getAccessibleAtlassianResources` if that fails.

## Decision Defaults

- Test case `type`: `integration` if the story spans ETL / migration / step functions / multi-system flows; `functional` otherwise.
- Test case `priority`: match the parent story priority by default. If the story relates to a `Bug` or `Error` issuetype with `High` or `Critical` priority via issuelinks, lift to `high`.
- Test case `status`: `active`.
- Estimated duration: realistic manual execution time (typically 45-180 minutes for integration coverage; 15-45 minutes for functional).
- Sub-task summary when creating: `QA Review`.
- Sub-task assignee when creating: the Atlassian user that triggered the skill.

## Tagging Conventions

The `.testcase.yml` `tags` array MUST include:

- The parent story key, lowercase (e.g., `im-707`).
- The epic key, lowercase, if present (e.g., `im-70`).
- The QA Sub-task key, lowercase (e.g., `im-725`).
- The functional area (e.g., `altru`, `migration`, `step-function`, `salesforce`).
- Any specific subdomain (e.g., `soft-credits`, `recognition-history`, `account-metrics`).
- The customer name if a concrete example is used (e.g., `tucson`).

Scenario-level tags should map ACs (`ac-1`, `ac-2`, ...), classify the scenario type (`happy-path`, `negative`, `edge-case`, `regression`, `regression-evidence`), and flag undocumented edge cases (`missing-doc`).

## Validation Checklist

Before reporting completion, verify:

- [ ] cloudId resolved.
- [ ] Parent story fetched; QA Sub-task resolved or created.
- [ ] If parent is `Rechazado`, user explicitly confirmed before generating.
- [ ] Every AC in the parent description is covered by at least one scenario.
- [ ] Every concrete example in the description is covered by one regression-evidence scenario.
- [ ] Every documented missing edge case has a `missing-doc` scenario or is explicitly listed in `## Riesgos abiertos del ticket`.
- [ ] `.testcase.yml` passes the `testcase-generator` validation checklist (UUID v4, unique key, valid gherkin, ISO-8601 timestamps).
- [ ] Jira description starts with `## Plan de pruebas QA` and contains all 8 required sections.
- [ ] Jira description ends with the `## Test case asociado` line pointing to the new file.
- [ ] Summary message includes Jira URL, file path, scenario count and any flagged risks.

## Example Reference

The IM-707 / IM-725 / TC-16 trio is the canonical reference for this skill's output:

- Parent story: IM-707 (Soft Credit Query Needed - Soft Credits Not Reflected on Constituent Record).
- QA Sub-task: IM-725 (description follows the section structure above).
- Test case: `test-cases/IM-707/IM-707-TC-16-altru-soft-credit-recognition-migration.testcase.yml`.

When in doubt about formatting or coverage depth, mirror that trio.
