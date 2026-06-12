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
3. Console summary with the Jira URL, the test case path, scenario count, flagged risks, and a suggestion to run `/qa-test-executor <TC-NN>` next.

Test run creation, PR review, regression checks, and evidence collection are owned by the companion `qa-test-executor` skill. Run that skill after this one whenever you are ready to validate the PR.

This skill DOES NOT commit or push. The user decides when to push.

## Workflow — Phase 1: Bundle creation

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
11. Summarize the result in one short message: Jira URL, file path, scenario count, flagged risks. End the summary suggesting `/qa-test-executor <TC-NN>` as the next step — the `qa-test-executor` skill takes over from here (PR review, unit-test inspection, technical + security regression, baseline vs post-fix, sandbox validation, test run creation). Do NOT auto-trigger execution; the user decides when to start it.

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
11. **Bundle ends at Phase 1. Execution lives in `qa-test-executor`.** Do NOT auto-run safesql baselines, unit tests, sandbox loads, or any evidence collection from this skill. Once `.testcase.yml` + Jira description are written, summarize and suggest `/qa-test-executor <TC-NN>`. The executor skill owns: PR classification, solution before/after, unit-test inspection, technical + security regression planning, safesql baseline vs post-fix, sandbox functional validation, test run YAML. Keeping creation and execution as separate user-triggered steps preserves composability (re-run executor after each commit on the PR without re-creating the bundle).
12. **Manual-step scenarios must be flagged explicitly.** Every scenario that depends on a human step (functional UI screenshots, sandbox reconciliation with savepoint+rollback, post-load verification, credential-protected runs) MUST be left as `not-run` in the test run with: a clear `notes:` block stating exactly what the user has to do, what evidence to capture (which screenshots, which list-view counts, which records), and where to drop the evidence (e.g., `attachments/<run>/<scenario>/`). The final user-facing summary message MUST end with a "Pendiente de tu parte" section that lists each manual scenario, what action is required, and what would close it.
13. **Pre-stage the functional UI scenario with a sandbox mock dataset when applicable.** When the issue is a migration / data-shape fix where the post-fix Salesforce state is observable in Lightning, and a sandbox is available (Veevart pattern: `IllinoisTrainingsSandbox`, `TucsonTrainingsSandbox`, etc.), do NOT leave the functional UI scenario as a passive "wait for the real load." Auto-execute up to the point where the user only has to capture screenshots. The expanded flow is described in [§ Sandbox mock-data pre-stage](#sandbox-mock-data-pre-stage) below.
14. **If you don't have access to the relevant Salesforce sandbox / org, ASK FOR IT — always.** Do not assume the user knows you need it. The moment the flow requires `sf` CLI login, browser-driven Lightning navigation, or any data write to a sandbox you are not yet authorized into, stop and request access with: (a) the exact sandbox / org name (`IllinoisTrainingsSandbox`, `TucsonTrainingsSandbox`, etc.), (b) the login URL (`https://test.salesforce.com` for sandboxes, `https://login.salesforce.com` for production), (c) the one-line bash command the user can run on their side OR the offer for you to launch the browser so they can log in interactively. Same applies to source DBs (safesql profiles) and Jira projects.
15. **State file is mandatory.** After EACH step in 1–11 completes, atomically write the `/tmp/qa-bundle-<PARENT-KEY>.json` per the State management section. On invocation, ALWAYS check for an existing state file BEFORE starting step 1. Never silently overwrite an `in-progress` state without asking the user. This allows the skill to survive harness compaction and supports the batch-bundle workflow (creating 4 bundles in a row for a QA Review queue without losing partial progress).

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

- [ ] On invocation: state file at `/tmp/qa-bundle-<PARENT-KEY>.json` was checked. If `in-progress` existed and the user opted to resume, `completedSteps` were honored.
- [ ] State file written atomically after each completed step (visible by checking `lastUpdated` increments).
- [ ] cloudId resolved.
- [ ] Parent story fetched; QA Sub-task resolved or created.
- [ ] If parent is `Rechazado`, user explicitly confirmed before generating.
- [ ] Every AC in the parent description is covered by at least one scenario.
- [ ] Every concrete example in the description is covered by one regression-evidence scenario.
- [ ] Every documented missing edge case has a `missing-doc` scenario or is explicitly listed in `## Riesgos abiertos del ticket`.
- [ ] `.testcase.yml` passes the `testcase-generator` validation checklist (UUID v4, unique key, valid gherkin, ISO-8601 timestamps).
- [ ] Jira description starts with `## Plan de pruebas QA` and contains all 8 required sections.
- [ ] Jira description ends with the `## Test case asociado` line pointing to the new file.
- [ ] Summary message includes Jira URL, file path, scenario count, flagged risks, the `/qa-test-executor` suggestion, and the path to the preserved state file.
- [ ] State file marked `status: completed` and moved to `<state>-completed.json` for audit.

## Example Reference

The IM-707 / IM-725 / TC-16 trio is the canonical reference for this skill's output:

- Parent story: IM-707 (Soft Credit Query Needed - Soft Credits Not Reflected on Constituent Record).
- QA Sub-task: IM-725 (description follows the section structure above).
- Test case: `test-cases/IM-707/IM-707-TC-16-altru-soft-credit-recognition-migration.testcase.yml`.

When in doubt about formatting or coverage depth, mirror that trio.

## Sandbox mock-data pre-stage

When the issue is the kind where the post-fix Salesforce state is observable in Lightning (migration query fixes, data-shape fixes, lookup population fixes, field mapping fixes, trigger / rollup behavior fixes), DO NOT leave the functional UI scenario at "wait for the real load." Instead, build the minimal mock dataset that recreates the post-fix state in a sandbox so the user only has to capture screenshots.

### When this applies

Apply this pre-stage when ALL of the following hold:

- The PR fix changes data that ends up in Salesforce (a SQL migration query, an ETL mapper, a target-org field projection, a trigger that affects rollups visible in UI).
- The fix's effect is observable on a Lightning record (a previously-blank lookup is now populated, a total now matches, a rollup now sums correctly, a status now transitions).
- A Veevart Trainings sandbox exists for the customer (or the user can name one) — typical patterns: `<customer>--trainings.sandbox.my.salesforce.com`.
- The source DB query for the fix is already validated via safesql (auto-execute scenarios 2-5 already PASSED).

Skip this pre-stage when:

- The issue is pure infrastructure / observability / docs (no Salesforce surface).
- The fix is too coupled to live prod data to be mocked meaningfully (e.g. requires real Account hierarchy, real payment processing, real external API).
- The user explicitly says "wait for the real load."

### Flow

1. **Ask for sandbox access if not yet authorized** (Rule 14). Launch the browser at `https://test.salesforce.com` and let the user log in interactively, OR run `sf org login web --instance-url https://<customer>--trainings.sandbox.my.salesforce.com --alias <customer>-trainings` so they complete it.
2. **Survey the sandbox.** Query the affected SObjects and parent lookups: how many records, how many have the external ID populated, what required fields exist, what validation rules will fire. Use `sf data query` and `sf sobject describe`. Identify the chain of dependencies (e.g. `Auctifera__Resources__c` parent → `Auctifera__Rental_Event__c` parent → `Auctifera__Rental_Resources__c` child).
3. **Extract the minimal source dataset** from the production-equivalent source DB via safesql: 5-10 rows from the affected universe (include 1 canonical example named in the Jira issue + N random representatives). Include ALL the parent external IDs needed to satisfy lookups. Save the raw JSON under `/tmp/<ISSUE>-sandbox-load-data.json`.
4. **Generate CSVs in dependency order** under `/tmp/<issue>-load/`:
   - Parents first (Resource Service, Rental Event, Account, etc.) with the source External IDs preserved (so the lookups by External_ID resolve).
   - Children last with the relationship-by-External-ID syntax: `<Lookup>__r.Auctifera__Implementation_External_ID__c`.
   - CSVs MUST be CRLF-terminated and end with a final CRLF, otherwise `sf data upsert bulk` rejects with `LineEnding is invalid on user data`. Use `python3` with `open('...', 'wb')` and explicit `\r\n` byte writes; do NOT trust `csv.DictWriter` newline kwargs.
   - Required-field gotchas (Veevart): `Auctifera__Rental_Event__c` requires `Auctifera__Client_Company_Household__c` (Account). `Auctifera__Rental_Resources__c` requires `Auctifera__Resource_Fee_Model__c` AND a per-person or flat-fee charge field populated (validation rule fires on blank). Discover these by parsing required createable fields from `sf sobject describe` and by reading any validation rule errors from the failed-records CSV after a first attempt.
5. **Upsert in dependency order** with `sf data upsert bulk --external-id Auctifera__Implementation_External_ID__c --line-ending CRLF --wait 5`. After each upsert, read the failed-records CSV if any rows failed and iterate on the CSV until 100% success.
6. **Query the inserted records back** to capture Lightning IDs for the Rental Resource / target object. Build the per-step screenshot table the user needs: one URL per spot-check record, one URL per lookup target, one URL for the list view.
7. **Hand off to the user** with:
   - A table mapping each TR scenario step (by `order:` in the test run YAML) to (a) the exact Salesforce Lightning URL to open and (b) the screenshot filename to save under `attachments/<run>/ui/`.
   - A 1-paragraph disclaimer making clear that the inserted records are a QA fixture that reproduces the target post-fix shape — NOT a real migration tool load — so the dev team or operator can trust QA evidence without confusing it with a production rehearsal.
   - The step in the test run (`scenarioIndex: <N>`) stays `not-run` with notes pointing to the table. Do NOT mark the scenario PASS until the user uploads screenshots and confirms.

### Veevart sandbox auth quick reference

```
sf org login web --instance-url https://<customer>--trainings.sandbox.my.salesforce.com --alias <customer>-trainings
sf org list                                         # confirm alias is Connected
sf data query --target-org <customer>-trainings --query "<SOQL>"
sf sobject describe --sobject <Object> --target-org <customer>-trainings
sf data upsert bulk --target-org <customer>-trainings --sobject <Object> --file <path>.csv --external-id <ExternalIdField__c> --line-ending CRLF --wait 5
sf data bulk results -o <customer>-trainings --job-id <id>   # inspect failed-records.csv
```

### Reference execution

IM-812 / TC-38 / TR-056 is the canonical reference for this pre-stage flow:

- Extracted 10 Rental Resource rows + 3 distinct VOLUNTEERTYPE parents + 10 RESERVATION parents from `illinois_2` via safesql.
- Upserted parents first (`Auctifera__Resources__c`, `Auctifera__Rental_Event__c`) with source-derived `Auctifera__Implementation_External_ID__c`, then the 10 `Auctifera__Rental_Resources__c` linked by `Auctifera__Resource__r.Auctifera__Implementation_External_ID__c` and `Auctifera__Rental_Event__r.Auctifera__Implementation_External_ID__c`.
- Discovered and worked around required fields: `Auctifera__Client_Company_Household__c` on Rental Event (used existing sandbox Account `001WI00001AmTESYA3`), `Auctifera__Resource_Fee_Model__c` + `Auctifera__Per_Person_Item_Charge__c` / `Auctifera__Resource_Flat_Fee_charge__c` on Rental Resource.
- Delivered per-step Lightning URL table to the user; Scenario 6 in TR-056 stayed `not-run` until screenshots were uploaded.

When in doubt about field discovery, CSV byte-encoding, validation-rule gotchas, or the per-step URL handoff format, mirror that execution.

## State management + context recovery

Bundle creation is lighter than execution but still benefits from persistent state — especially when generating multiple bundles back-to-back (e.g. the QA Review queue) and when the harness compacts mid-batch.

### State file location

`/tmp/qa-bundle-<PARENT-KEY>.json` — one file per parent ticket. Persisted while the bundle is in progress; deleted (or archived) once Phase 1 completes successfully.

### State schema (JSON, version 1)

```json
{
  "version": 1,
  "skill": "qa-bundle-generator",
  "parentKey": "IM-899",
  "qaSubTaskKey": "IM-903",
  "startedAt": "2026-06-11T08:00:00Z",
  "lastUpdated": "2026-06-11T08:12:00Z",
  "status": "in-progress",
  "completedSteps": [1, 2, 3, 4, 5, 6, 7],
  "currentStep": 8,
  "data": {
    "parentSummary": "Support date filters in donation opportunity extraction",
    "coverageSignals": {
      "acs": ["AC1...", "AC2...", "AC3...", "AC4..."],
      "concreteExamples": [],
      "missingEdges": [],
      "risks": []
    },
    "scenarioSet": [
      { "title": "...", "tags": ["..."], "given": ["..."], "when": ["..."], "then": ["..."] }
    ],
    "nextTCKey": "TC-54",
    "uuid": "39e8cf1e-f604-4022-ab4f-c67ca587805f",
    "testCasePath": "test-cases/IM-899/IM-899-TC-54-...yml"
  }
}
```

### Save protocol

After each of steps 1–11 completes, atomic write:
1. Build state in memory.
2. `python3 -c "import json; json.dump(state, open('<path>.tmp', 'w'), indent=2)"`.
3. `mv <path>.tmp <path>`.
4. Keep total size < 20 KB; for long descriptions, store path references rather than full content.

### Externalization rules

- Parent ticket description and PR diff: read once via Jira/gh, parse for signals, then DROP the raw text. Keep only the extracted signals (ACs, examples, edges, risks) in state.
- Do not keep multiple full Jira issue JSONs in conversation. Fetch → extract → externalize → reference.

### Resume protocol

On EVERY invocation:
1. Compute `/tmp/qa-bundle-<PARENT-KEY>.json` path from the input.
2. If a state file exists:
   - If `status: completed` → "bundle ya creado para IM-XXX. ¿Mostrar resumen o regenerar?"
   - If `status: in-progress` → "Estado previo encontrado (último paso <N>). ¿Resumir desde el paso <N+1>?"
3. If resume → load `data.*` into working memory, skip `completedSteps`, continue from `currentStep`.
4. If start-fresh → archive to `<state>.archived-<timestamp>.json`, restart from step 1.

### Cleanup on success

When step 11 (suggest `/qa-test-executor <TC-NN>`) is reached:
- Set `status: completed` in the state file.
- Move from `/tmp/qa-bundle-<PARENT-KEY>.json` → `/tmp/qa-bundle-<PARENT-KEY>-completed.json`.
- Include in the summary: "State preserved at `<path>`. Run `/qa-test-executor <TC-NN>` to continue with execution."

### Context-pressure heuristics

Same triggers as `qa-test-executor` (see that skill's State management section): "Output too large" results, > 50 tool calls without compaction, response truncation, user mentions context. When fired:
1. Force-save state.
2. Tell the user: "Estado guardado en `<path>`. Re-invoca `/qa-bundle-generator <PARENT-KEY>` para resumir desde el paso <currentStep>."
3. Stop the current turn.

### Cross-skill state handoff

The bundle state file is independent from the executor state file. Phase 1 completion does NOT auto-populate Phase 2 state — the executor reads from the `.testcase.yml` it created, not from this state. This keeps the two skills decoupled (you can run `/qa-bundle-generator` on machine A and `/qa-test-executor` on machine B).
