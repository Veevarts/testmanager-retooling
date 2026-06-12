# QA Test Executor

Execute the test plan for a Jira QA bundle: read the PR, classify the change, inspect the dev's unit tests, plan technical + security regression, run baselines vs post-fix, validate functional behavior, and write the `.testrun.yml` with PASS/FAIL evidence.

Agent identity for this skill: `codex` — direct, technical, concise, QA-focused.

This skill is the execution counterpart to `qa-bundle-generator`. Run `qa-bundle-generator` first to create the bundle (Jira QA Sub-task plan + `.testcase.yml`); then run this skill to execute it.

## Trigger

When the user asks to:
- Execute a test case / run the test plan for a Jira story.
- Validate a PR against an existing test case.
- "ejecuta TC-XX", "/qa-test-executor", "valida IM-XXX contra el PR", "corre la regresión de TC-NN", "ejecuta el plan de pruebas".

Do NOT trigger when:
- The user only wants the plan (use `qa-bundle-generator` instead).
- No `.testcase.yml` exists yet for the target ticket (tell them to run `/qa-bundle-generator` first).

## Inputs

Accepts any of:
- A test case key (e.g., `TC-54`) — skill resolves the `.testcase.yml` path and parent ticket.
- A Jira story key (e.g., `IM-899`) — skill resolves the associated test case.
- A test case path (e.g., `test-cases/IM-899/IM-899-TC-54-...yml`) — direct.

If multiple TCs exist for the same parent → ask once.

## Outputs

1. `.testrun.yml` under `test-runs/<date>/tr-<NN>-tc-<NN>.testrun.yml` with every scenario marked PASS/FAIL or `not-run` with explicit handoff notes.
2. Evidence files under `attachments/tr-<NN>-tc-<NN>/` organized by scenario (`scenario-0-unit-tests/`, `scenario-1/`, …, plus `regression-plan.txt`, `regression-results.txt`, and `owasp-top10-scan.txt`).
3. Defects raised in Jira (with `jiraKey` + `url`) linked to the parent ticket for every FAIL or High/Critical security finding (including OWASP Applicable+FAIL).
4. Final summary message: classification, solution summary, unit tests status, technical regression status, security regression status, OWASP Top 10 status, pass rate, defects raised, and the "Pendiente de tu parte" section listing every `not-run` scenario.
5. A commit + push to `main` containing the testcase, testrun, and attachments so TestManager can ingest the evidence (Step 12). Commit URL surfaced in the final summary.

This skill commits + pushes the QA artifacts to `main` after writing the TR — TestManager only ingests what it sees on `main`. Large files (>50 MB) are excluded from the commit and replaced by a `summary.json` substitute.

## Workflow

### Step 1: Resolve inputs, load the test case, locate the PR

- Resolve TC key → `.testcase.yml` path via `grep "^key:" test-cases/**/*.testcase.yml`.
- Read the YAML to capture parent ticket key, scenarios, tags, preconditions.
- Fetch parent ticket via `mcp__atlassian__getJiraIssue` (`responseContentFormat: markdown`).
- Find the PR:
  - Look in description for `github.com/<org>/<repo>/pull/<n>`.
  - If absent, look in issuelinks or labels for a branch name (`task/...-<KEY>`, `bug/...-<KEY>`) → resolve with `gh pr list --search "head:<branch>"`.
  - If still absent → ask the user ONCE for the PR URL.

### Step 2: Classify the change scope from the PR

```
gh pr view <n> --json title,body,headRefName,baseRefName,files,additions,deletions
gh pr diff <n> --name-only
```

Routing table:

| Category | Detection signal | Strategy | Continues to |
|---|---|---|---|
| **SQL-only** | All changes are `**/*.sql` or SQL fixtures | safesql baseline vs post-fix on named profiles | step 7 → 8 |
| **Pipeline / extractor** | TypeScript/Python pipeline + spec files (`.ts`, `.py`, `*.spec.ts`) | Run extractor with controlled input; capture deltas | step 7 → 8 |
| **Salesforce-bound** | Produces CSVs / payloads that load into a SF org | Stage CSVs + 7-field write + insert to trainings sandbox | step 7 → 8 → 9 |
| **UI / Frontend-only** | Vue/React/HTML/CSS/component files; no SQL/pipeline | DO NOT execute automatically. Prepare detailed manual scenarios with expected states + screenshot markers | step 7 (UI branch) → 10 |
| **Docs-only** | Only `.md` / `docs/**` changes | Validate scope-match between docs and ticket; minimal execution | step 10 |
| **Mixed** | Combination of the above | Apply each surface's strategy in parallel; aggregate | combination |

Write classification + 1-line rationale into `environment.buildVersion` of the test run.

### Step 3: Understand the solution — before/after of the repo

```
gh pr diff <n>
```

For each substantive file (skip rename-only, formatter-only):
- Identify the precise change (predicate widened, column joined, method extracted, fallback added).
- Write a 1-paragraph **Solution Summary**: what was wrong, what the fix does, why it works, side effects to expect.

Persist into the test run's run-level `notes:` under a `## Solution understood` block. Surface it again in the final handoff (step 10).

### Step 4: Inspect unit / integration tests in the PR

```
gh pr diff <n> --name-only | grep -iE "(spec|test|__tests__|\.test\.|fixtures?)"
```

For each test file added or modified by the PR:
- Read its content.
- Map each test case to which AC of the parent story it covers.
- Compute a coverage matrix: AC → test files referenced.
- Identify gaps: ACs NOT covered by any unit / integration test.

Run the tests on the PR branch:
- Node: `npm test -- --runInBand <pattern>` or `npx jest <path>`.
- Python: `pytest <path> -v`.
- Other: the project's standard runner.

Decisions:
- **Tests fail on PR branch → STOP and raise as defect immediately.** PR is not ready for QA; do not continue execution.
- **Tests pass + coverage matches ACs → green flag.** Note in regression plan as "covered by dev tests".
- **Tests pass but coverage gaps exist → flag gaps in regression plan (step 5).** These ACs need additional manual / safesql evidence.
- **No tests in the PR for a substantive code change → flag as Medium risk** in the regression plan ("dev did not add coverage; QA must compensate with full safesql + sandbox validation").

Persist to `attachments/<run>/scenario-0-unit-tests/`:
- `tests-found.txt` (list of test files + assertion count + ACs mapped).
- `coverage-matrix.txt` (AC ↔ test mapping + gaps).
- `test-run-log.txt` (stdout / stderr from running the suite on PR branch).

### Step 5: Plan technical + security regression

Identify regression items BEFORE running anything, so the execution in step 7-8 covers them.

**Technical regression — does the fix break the normal flow it touches?**

For each changed file, identify the surfaces that depend on it:
- **SQL changes**: `grep -rn "<table>\." **/*.sql` and `grep -rn "<column>" **/*.sql` to find other queries that use the same tables / columns / joins. Identify dashboards / reports / extractors that consume the same data.
- **Pipeline changes**: `grep -rn "<changedFunction>" **/*.{ts,js,py}` to find call sites. Identify downstream extractors / specs that depend on the changed signature or return shape.
- **UI changes**: `grep -rn "from.*<changedComponent>" **/*.{tsx,vue}` to find importers. Identify other pages / views that render the component.
- **SF-bound changes**: SOQL the affected SObjects in the sandbox for existing records that would be touched by the new logic.

For each surface, decide if the PR could break its happy path. List items as Low / Medium / High risk.

**Security regression — does the diff introduce new vulnerabilities?**

Run all of:
- **SQL injection**: `git diff <merge-base> HEAD -- '*.sql' '*.ts' '*.py' | grep -iE "(SELECT|INSERT|UPDATE|DELETE).*\+.*\$"` to detect string-concatenated SQL. Parameterized binding must remain.
- **Secrets in diff**: `git diff <merge-base> HEAD | grep -iE "(password|api[_-]?key|secret|token|bearer|\.env)"` plus look for JWT-shaped strings and private keys (`-----BEGIN`).
- **PII exposure**: in changed files, grep for `console.log`, `logger.info`, `print(` followed by anything that touches `email`, `phone`, `ssn`, `dob`, `address`.
- **Auth / RBAC**: check if profiles, permission sets, sharing rules, OAuth scopes, or role assignments were touched. Verify no privilege escalation (e.g., new field readable by `Read Only` profile that wasn't before).
- **Dependencies**: scan `package.json` / `requirements.txt` for new entries. Run `npm audit --json` or `pip-audit` on the PR branch. Flag any High/Critical advisories.
- **Injection vectors (UI)**: grep changed JSX/Vue templates for unescaped interpolation (`v-html`, `dangerouslySetInnerHTML`), DOM `eval`, `new Function(`, `document.write`. Grep for command injection (`exec`, `spawn`, `child_process`) with user-controlled inputs.

Build the regression matrix:

```
| Item | Type | Risk | Check method | Verdict |
|---|---|---|---|---|
| dashboard_donations_summary.sql uses same join | Technical | Medium | safesql baseline vs post-fix on dashboard query | TBD |
| QueryBuilder.ts:42 string concat in WHERE clause | Security | High | grep + manual review | TBD |
| New npm package csv-parser@^4.0.0 | Security | Low | npm audit; check Advisory DB | TBD |
| Profile `Migration Engineer` modified | Security | High | sf describe + permission delta | TBD |
| ExportButton component referenced by 3 other views | Technical | Low | manual UI walkthrough on each view | TBD |
```

Persist to `attachments/<run>/regression-plan.txt`.

### Step 6: Verify execution access; request access once if missing

Conditional on routing:

- **SQL / safesql path**: `safesql --list-profiles` (or `ls /Users/veevart/tools/safesql/profiles/`). Verify the profiles named in the ticket evidence are reachable. Test with `SELECT 1`.
- **Salesforce path**: `sf org list --json`. Verify trainings sandbox alias exists for the customer in scope.
- **Pipeline path**: confirm Node version + `npm install` state + required env vars.
- **UI path**: no access required.

If access is missing → stop and ask ONE concrete question covering everything you need. Do not split into multiple turns. Example:

> "Necesito el profile safesql `high-desert` para Scenario 1, y un alias `sf` autenticado contra `illinois-trainings` para Scenario 5. ¿Puedes conectarlos / dame el comando que ejecuto?"

Do not invent fixtures. Do not fall back to synthetic data unless the ticket explicitly accepts it OR the qa-bundle-generator Sandbox mock pre-stage pattern applies.

### Step 7: Execute according to the routing strategy

Save evidence under `attachments/<run>/scenario-<N>/` with stable filenames.

**SQL-only / SQL part of Mixed:**
1. `git checkout $(git merge-base origin/main <PR-branch>)` to get pre-fix.
2. Run the unmodified query against each profile with safesql → capture row count + SUMs + sample 10 rows by PK → save as `baseline-<profile>.csv` + `baseline-<profile>-summary.txt`.
3. `git checkout <PR-branch>` to get post-fix.
4. Re-run → save as `post-fix-<profile>.csv` + `post-fix-<profile>-summary.txt`.
5. safesql is read-only by design; never bypass.

**Pipeline / extractor:**
1. Identify test fixture / representative input from the spec file changed in the PR.
2. Run pipeline pre-fix + post-fix with the same input → capture stdout/stderr/output files side-by-side.

**Salesforce-bound:**
1. SQL/Pipeline validation first.
2. Stage CSVs in dependency order (parent → child).
3. Require 7-field write confirmation BEFORE insert: target org, operation, object API name, row count, payload path, side effects, verification/rollback plan.
4. Insert into trainings sandbox with isolation prefix `qa-<TC-NN>-<random>` for one-SOQL rollback.
5. Reference qa-bundle-generator § Sandbox mock-data pre-stage for CRLF / required-field / dependency-order details.

**UI-only:**
1. DO NOT execute.
2. Write detailed manual scenarios with `expectedBehavior:` per step: URL/route to open, role, click/input action, observable to verify (DOM element, computed style, count badge, toast).
3. Include `screenshot-needed: yes` markers and the relative path under `attachments/<run>/ui/`.
4. Mark every UI scenario `status: not-run`. Run-level `status: in-progress`.

**Docs-only:**
1. Read changed docs.
2. Verify they match the scope described in the ticket (no scope creep, no missing sections).
3. Capture diff in scenario notes; mark PASS if scope-fit holds.

### Step 8: Compare outputs + count deltas + execute regression checks

**Original AC evidence** — comparison matrix per scenario:
- Row count delta per object/query.
- Column-by-column diff for affected fields (`sf data query` + `diff`, `csv-diff`, or `python3 -c "import csv; ..."`).
- Sum / aggregate deltas.
- Sample row inspection for canonical examples named in the ticket.

Map each delta to one or more ACs. Any delta not mappable → flag as **unexpected side effect** in the scenario's `defects` array (even good surprises are bugs).

Persist as `attachments/<run>/scenario-<N>/comparison-matrix.txt` with columns `Profile | Metric | Baseline | Post-fix | Delta | AC reference | Verdict`. Mirror the format of `attachments/tr-062-tc-51/scenario-4/data-comparison-matrix.txt`.

**Technical regression execution** — run the items from step 5's matrix:
- For each Technical item: run its `Check method` (safesql query on the dependent surface, manual UI walkthrough notes, etc.) → expect delta 0 unless the PR explicitly says the dependent surface changes too.
- Any non-zero delta on a dependent surface that the PR did NOT advertise → defect.

**Security regression execution** — run the items from step 5's matrix:
- For each Security item: produce its check output (grep results, `npm audit` JSON, permission delta).
- Any item flagged High or Critical → STOP, raise as defect, mark related scenarios `blocked`, surface in summary.
- Persist results to `attachments/<run>/regression-results.txt` with each item's Verdict filled in (PASS / FAIL / BLOCKER).

### Step 9 (conditional): Validate end-to-end in Salesforce sandbox

Trigger only when at least one is true:
- PR classified Salesforce-bound (step 2).
- The fix's effect is observable in Lightning (lookup populated, rollup correct, status transition).
- A Veevart trainings sandbox is available (`<customer>--trainings.sandbox.my.salesforce.com`).

Follow qa-bundle-generator § Sandbox mock-data pre-stage verbatim:
1. Ask for sandbox access if not yet authorized.
2. Survey the sandbox (record state, validation rules, required fields).
3. Extract minimal source dataset via safesql.
4. Generate CSVs in dependency order, CRLF-terminated.
5. Upsert with `sf data upsert bulk` after the 7-field gate.
6. Capture per-step Lightning URLs + screenshot filenames for the user.
7. Leave the functional UI scenario `not-run` until the user uploads screenshots.

Always provide the rollback SOQL one-liner in the scenario notes.

### Step 10: OWASP Top 10 (2021) applicability scan + final security verdict

Apply at the END of all execution, BEFORE writing the test run. The point is to make sure nothing on the OWASP Top 10 was silently introduced — even when the regression matrix (step 5) focused only on what the PR obviously touches. Most categories will be `N/A` depending on the PR surface; that is expected and correct. **N/A still needs a 1-line justification.**

For each of the 10 categories, decide: `Applicable` (Yes/No), `Check method`, `Verdict` (PASS / FAIL / N/A), `Evidence`.

| ID | Risk | When applicable | Check method |
|---|---|---|---|
| **A01** | Broken Access Control | PR touches auth, permissions, profiles, sharing rules, RBAC, route guards, SOQL with `WITH SECURITY_ENFORCED` removed, IDOR-prone endpoints | Diff for permission changes; verify principle of least privilege; check direct object reference without auth |
| **A02** | Cryptographic Failures | PR handles passwords, tokens, PII at rest, TLS config, hashing algorithms, encryption keys | No hardcoded secrets; modern algorithms only (no MD5/SHA1 for passwords, no DES); TLS 1.2+; PII encrypted at rest where required |
| **A03** | Injection | PR builds SQL / NoSQL / OS commands / LDAP / XPath / user-controlled HTML | Parameterized queries only; no string concatenation in dynamic queries; input validation; output encoding for HTML/JS contexts. Re-run grep patterns from step 5 |
| **A04** | Insecure Design | PR introduces new business logic, new threat surface, missing rate limiting, missing fraud / abuse checks | Threat-model alignment review; verify rate limiting on new endpoints; check business-logic abuse vectors |
| **A05** | Security Misconfiguration | PR touches infra-as-code, env vars, default credentials, debug toggles, CORS config, security headers, error verbosity | No defaults left enabled; minimal verbose error messages; CORS least-permissive; security headers present |
| **A06** | Vulnerable and Outdated Components | PR adds/updates `package.json`, `requirements.txt`, `Pipfile`, `pom.xml`, `Cargo.toml`, or any lockfile | `npm audit --json`, `pip-audit`, or equivalent. Any High/Critical advisory = FAIL |
| **A07** | Identification and Authentication Failures | PR touches login flows, session handling, MFA, password reset, token issuance/validation | Secure session management; no credentials in URLs; rate limiting on auth endpoints; secure password reset tokens |
| **A08** | Software and Data Integrity Failures | PR touches CI/CD pipelines, deserialization, plugin/update systems, package signing | Verified signatures on updates; no insecure deserialization (`pickle.loads(user_input)`, `eval()`, unsafe YAML loaders); integrity checks on critical writes |
| **A09** | Security Logging and Monitoring Failures | PR adds new endpoints/operations, removes logging, changes log levels, modifies audit trails | Critical events logged (auth failures, access denials, input validation failures); no PII in logs; logs reach centralized destination |
| **A10** | Server-Side Request Forgery (SSRF) | PR introduces server-side HTTP calls (fetch / axios / requests) where URL is user-influenced | URL allowlist; no raw user input in URL; metadata endpoints (`169.254.169.254`) blocked; egress filtered |

Persist the scan to `attachments/<run>/owasp-top10-scan.txt`:

```
| ID  | Risk                       | Applicable | Check method                          | Verdict | Evidence / Justification |
|-----|----------------------------|------------|---------------------------------------|---------|--------------------------|
| A01 | Broken Access Control      | No         | -                                     | N/A     | PR is SQL-only extraction; no auth surface touched |
| A02 | Cryptographic Failures     | No         | -                                     | N/A     | No credential or PII handling in scope |
| A03 | Injection                  | Yes        | grep step 5 patterns; safesql binding | PASS    | All filters use @params; no string concat in donation_transaction.sql |
| A04 | Insecure Design            | No         | -                                     | N/A     | Bug fix, no new business logic |
| A05 | Security Misconfiguration  | No         | -                                     | N/A     | No config / infra files touched |
| A06 | Vulnerable Components      | No         | -                                     | N/A     | No dependency changes (package.json untouched) |
| A07 | Authentication Failures    | No         | -                                     | N/A     | No auth surface touched |
| A08 | Integrity Failures         | No         | -                                     | N/A     | No CI/CD or deserialization touched |
| A09 | Logging Failures           | No         | -                                     | N/A     | No log changes; observability-neutral |
| A10 | SSRF                       | No         | -                                     | N/A     | No outbound HTTP calls introduced |
```

**Decisions:**
- **Applicable + FAIL** → raise as defect with severity = Critical for A01/A03/A06/A07/A10 (active exploit class), High for A02/A05/A08, Medium for A04/A09. Mark related scenarios `blocked`. Surface in summary as a security blocker.
- **Applicable + verdict TBD** → cannot ship; halt and ask the user (do not write the test run with a TBD verdict).
- **N/A** items still require a 1-line justification — never leave the cell empty.
- Mark `N/A` liberally. Faking PASS on a surface the PR did not touch dilutes the signal of real PASS results.

**Reference standards** (cite in evidence when used):
- OWASP Top 10:2021 (canonical reference for this scan).
- For deeper validation: OWASP ASVS Level 1 (basic) checks on the changed surface.
- For API-heavy backend changes: also apply OWASP API Security Top 10 categories where they overlap.

### Step 11: Write `.testrun.yml`, raise defects, summarize handoff

1. **Re-scan TR keys IMMEDIATELY before writing** (`grep -h "^key:" test-runs/**/*.testrun.yml | sort -V | tail` + `git fetch && git log origin/main -- test-runs/`). Use `max(local, remote) + 1`. Avoids collision with TestManager UI auto-commits that may grab the key mid-session.
2. **Follow the actual TestManager schema** (mirror a recently-rendered TR like `tr-062-tc-51` if testrun-generator skill disagrees):
   - `id: tr-<uuid>` unquoted.
   - `key: TR-<NN>` unquoted.
   - One `results[]` entry per scenario (NOT per test case).
   - Each entry has `scenarioTitle` + `scenarioIndex` + `stepResults[]` for that scenario only.
   - Run-level `status:` enum: `planned | in-progress | completed | aborted` (NOT `passed`).
   - Scenario-level + step-level `status:` enum: `not-run | passed | failed | blocked | skipped`.
   - `history[].to:` respects the enum of its level.
   - `executedAt` is OMITTED on `not-run` scenarios (empty string fails zod validation).
3. **Attach evidence**: every `then` step that produced a file references it under `attachments:` with `{name, path, mimeType, size}` objects.
4. **Defects**: any FAIL or Security High/Critical → `mcp__atlassian__createJiraIssue` linked to the parent ticket. Capture the new key + url in the scenario's `defects` array as `{jiraKey, url, severity, summary}`.
5. **Commit + push the QA artifacts so TestManager can ingest them.** See Step 12.
6. **Final summary message** must include, in this exact order:
   - Test run key + path.
   - Classification (step 2) + Solution Summary (1-line from step 3).
   - Unit tests status: `PASS / FAIL / gaps detected` with the AC↔test coverage matrix link.
   - Technical regression status: `<N>/<M> items PASS · <K> items FAIL`.
   - Security regression status: `<N>/<M> items PASS · <K> items FAIL · <H> High/Critical blockers`.
   - **OWASP Top 10 status**: `<A> applicable · <P> PASS · <F> FAIL · <NA> N/A`. If any Applicable + FAIL → surface the category id (e.g. `A03 Injection`) as a blocker line.
   - Pass rate: `<X>/<Y> scenarios PASS · <Z> not-run`.
   - Defects raised: list of Jira keys + URLs.
   - **"Pendiente de tu parte"** section: every `not-run` scenario, what the user must do to close it, what evidence to capture, where to drop it.

### Step 12: Commit + push the QA artifacts (so TestManager can ingest them)

The QA artifacts are useless to TestManager until they land on `main`. Always commit + push after the TR is written (and after the user has reviewed any FAIL scenarios that need their judgment).

1. **What to commit**: `test-cases/<PARENT-KEY>/`, `test-runs/<date>/tr-<NN>-tc-<NN>.testrun.yml`, `attachments/tr-<NN>-tc-<NN>/`. NEVER `git add -A` — only add the QA artifacts explicitly.
2. **Pre-commit hygiene**:
   - Skip files > 50 MB on commit (push will warn and TestManager won't ingest them). For evidence files larger than 50 MB (e.g. full baseline/post-fix JSON dumps), keep them locally referenced from the comparison-matrix but exclude them from the commit. Replace with a smaller `summary.json` containing row count + first 20 sample rows.
   - Re-run the TR key re-scan one more time (`grep -h "^key:" test-runs/**/*.testrun.yml | sort -V | tail`) — the UI may have committed a TR in the seconds since the last scan.
3. **Commit message format**: `test(<PARENT-KEY>): TC-<NN> + TR-<NN> <pass>/<total> <verdict> for <1-line summary>` followed by a paragraph with the scenario-by-scenario verdicts. End with the standard `Co-Authored-By` line.
4. **Push**: `git push origin main`.
5. **Confirm TestManager can ingest**: include the GitHub commit URL or PR URL in the final summary. The user will trigger a re-import in the TestManager UI (or it polls main automatically).
6. **If a FAIL or security blocker exists**: still commit (TestManager needs the artifact to show the failure), but in the final summary explicitly call out "QA verdict: FAIL — defect <JIRA-KEY> raised; do not transition the parent story until the defect is closed."

## Rules

1. **Execution requires a bundle.** If no `.testcase.yml` exists for the input → tell the user to run `qa-bundle-generator` first. Never invent a TC during execution.
2. **PR is mandatory.** If no PR can be resolved from the parent ticket → ask once. Without a PR there is nothing to validate against.
3. **Re-scan TR keys at write time.** TestManager UI can create runs mid-session; rescan right before commit (memory: `feedback-testmanager-ui-creates-runs-mid-session`).
4. **Schema enum strictness.** Run-level `status:` is `planned | in-progress | completed | aborted` (NOT `passed`). Scenario-level is `passed | failed | not-run | blocked | skipped`. Mixing them fails zod validation (memory: `feedback-testmanager-actual-schema`).
5. **Spanish in evidence + handoff.** `actual:`, `notes:`, `history.reason:` all in Spanish. Gherkin step titles inherited from the TC stay as the TC has them (override allowed if the TC was created with Spanish gherkin per memory `feedback-gherkin-in-spanish`).
6. **Tests fail on PR → defect immediately.** Do not continue execution past step 4. The PR is not ready for QA.
7. **Security regression High/Critical → block immediately.** Raise defect, mark related scenarios `blocked`, surface in summary as a blocker line.
   - This applies both to the PR-surface regression items (step 5/8) AND the OWASP Top 10 scan (step 10). An OWASP Applicable + FAIL on A01/A03/A06/A07/A10 = Critical defect; A02/A05/A08 = High; A04/A09 = Medium. Never write the test run while any Applicable item has verdict `TBD`.
8. **Auto-execute everything that doesn't need a human.** safesql queries, unit tests, regression checks, schema audits, security scans — all run without asking. Stop only when sandbox/SF write access is required, or when a security blocker fires, or when credentials are missing (memory: `feedback-execute-auto-flag-manual`).
9. **Sandbox writes require 7-field confirmation.** No exceptions: target org, operation, object API name, row count, payload path, side effects, verification/rollback plan.
10. **Always commit + push the QA artifacts after the TR is written.** Step 12 is mandatory: TestManager only sees what lands on `main`. Skip the commit only when a FAIL needs user adjudication first, but document explicitly why you stopped (and complete the commit immediately after the user approves).
11. **One TR per execution session.** If the user re-runs the executor for the same TC, bump as a new TR with new key — never overwrite history.
12. **Coverage gap is not auto-FAIL but always flagged.** If unit tests in the PR don't cover an AC, the scenario for that AC is still executed (via safesql / sandbox), but the gap is surfaced in the summary as "dev did not add coverage; QA covered via <evidence>".
13. **State file is mandatory.** After EACH step in 1–10 completes, atomically write the `.skill-state.json` per the State management section. On invocation, ALWAYS check for an existing state file BEFORE starting step 1. Never silently overwrite an `in-progress` state without asking the user. This is what makes the skill survive harness compaction and allows re-invocation after a session restart.

## Validation Checklist

Before reporting completion:

- [ ] On invocation: state file checked. If `in-progress` existed and the user opted to resume, `completedSteps` were honored (no re-execution of finished steps).
- [ ] State file written atomically after each completed step (visible by checking `lastUpdated` increments).
- [ ] TC resolved + parent ticket fetched + PR located.
- [ ] Classification + Solution Summary written into TR (`environment.buildVersion` + run-level `notes`).
- [ ] Unit tests inspected; run result captured under `scenario-0-unit-tests/`; AC↔test coverage matrix complete.
- [ ] Regression plan (technical + security) persisted under `attachments/<run>/regression-plan.txt` with no `TBD` left at write time.
- [ ] Required access verified (or requested with single concrete question if missing).
- [ ] Every scenario has either PASS/FAIL with evidence OR `not-run` with explicit "Pendiente de tu parte" notes.
- [ ] Comparison matrix exists for every SQL/Pipeline/SF scenario.
- [ ] Regression results persisted in `regression-results.txt`; no Tech/Sec items left `TBD`.
- [ ] OWASP Top 10 scan persisted in `owasp-top10-scan.txt`; all 10 categories decided (Applicable + verdict OR N/A + justification); no `TBD` left.
- [ ] No Applicable OWASP item with verdict FAIL is left without a corresponding defect raised in Jira (severity per Rule 7).
- [ ] Defects raised in Jira for every FAIL with `jiraKey` + `url` + severity.
- [ ] TR key re-scanned at write time (no collision with TestManager UI commits).
- [ ] Run-level and scenario-level `status:` use the correct enums.
- [ ] Final summary includes classification, solution summary, unit tests, technical regression, security regression, **OWASP Top 10 status**, pass rate, defects, "Pendiente de tu parte", and the path to the preserved state file.
- [ ] State file marked `status: completed` and moved to `.skill-state-completed.json` for audit.
- [ ] Artifacts (testcase + testrun + attachments) committed and pushed to `main` so TestManager can ingest them. Commit URL captured in the final summary. Large files (>50 MB) excluded with a `summary.json` substitute.

## Tooling reference

```bash
# PR review
gh pr view <n> --json title,body,headRefName,baseRefName,files
gh pr diff <n>
gh pr diff <n> --name-only

# safesql baseline vs post-fix
git checkout $(git merge-base origin/main <PR-branch>)
safesql --profile <name> --query queries/<file>.sql > baseline.csv
git checkout <PR-branch>
safesql --profile <name> --query queries/<file>.sql > post-fix.csv

# Unit tests
npm test -- --runInBand <pattern>
npx jest <path>
pytest <path> -v

# Security regression scans
git diff $(git merge-base origin/main HEAD) HEAD -- '*.sql' '*.ts' '*.py' | grep -iE "(SELECT|INSERT|UPDATE|DELETE).*\+.*\$"
git diff $(git merge-base origin/main HEAD) HEAD | grep -iE "(password|api[_-]?key|secret|token|bearer|\.env|-----BEGIN)"
npm audit --json
pip-audit

# Salesforce
sf org list --json
sf data query --target-org <alias> --query "SELECT COUNT() FROM <Object>"
sf sobject describe --sobject <Object> --target-org <alias>
sf data upsert bulk --target-org <alias> --sobject <Object> --file <path>.csv --external-id <Field> --line-ending CRLF --wait 5
sf data bulk results --target-org <alias> --job-id <id>
```

## Example reference

When in doubt about TR format, mirror `test-runs/2026-06-09/tr-062-tc-51.testrun.yml` (5/5 PASS, full attachment structure, history with completed transition, dual prefix isolation pattern).

For sandbox mock-data details (CSV byte-encoding, dependency order, required-field gotchas, per-step Lightning URL handoff format), mirror IM-812 / TC-38 / TR-056 as documented in `qa-bundle-generator` § Sandbox mock-data pre-stage.

## State management + context recovery

Long QA executions (SQL baselines + post-fix + unit tests + regression scans + sandbox loads + OWASP) can exceed the harness's automatic context compaction threshold. To survive a compaction or a deliberate session restart, persist progress incrementally to a state file and resume from there on the next invocation.

### State file location

- Canonical (once the run folder exists): `attachments/tr-<NN>-tc-<NN>/.skill-state.json`.
- Pre-canonical (during steps 1–5, before the TR key is known and before any attachments/ folder exists): `/tmp/qa-executor-<TC-KEY>.json`. Once the TR key is computed (step 10) and the attachments folder is created, migrate via `mv` and update the pointer.

### State schema (JSON, version 1)

```json
{
  "version": 1,
  "skill": "qa-test-executor",
  "parentKey": "IM-899",
  "tcKey": "TC-54",
  "trKey": "TR-063",
  "prNumber": 125,
  "startedAt": "2026-06-11T08:00:00Z",
  "lastUpdated": "2026-06-11T09:15:00Z",
  "status": "in-progress",
  "completedSteps": [1, 2, 3, 4, 5],
  "currentStep": 6,
  "data": {
    "classification": { "category": "SQL-only", "rationale": "..." },
    "solutionSummary": "1-paragraph plain-language explanation",
    "unitTests": {
      "filesFound": ["query-regression/donation-transaction.spec.ts"],
      "coverageMatrix": { "AC1": ["test name 1"], "AC2": [] },
      "gapsACs": ["AC2"],
      "runResult": "PASS",
      "runLog": "attachments/<run>/scenario-0-unit-tests/test-run-log.txt"
    },
    "regressionPlan": [
      { "item": "...", "type": "Technical", "risk": "Medium", "checkMethod": "...", "verdict": "TBD" }
    ],
    "verifiedAccess": { "safesql": ["illinois", "high-desert"], "sf": ["illinois-trainings"] },
    "scenarioResults": [
      { "scenarioIndex": 0, "status": "passed", "evidencePath": "...", "completedAt": "..." }
    ],
    "owasp": {
      "A01": { "applicable": false, "verdict": "N/A", "justification": "PR is SQL-only" }
    },
    "defectsRaised": [
      { "jiraKey": "IM-905", "url": "...", "scenarioIndex": 2, "severity": "High" }
    ]
  }
}
```

### Save protocol

After EACH of steps 1–10 completes, write the state file atomically:
1. Build the updated state object in working memory.
2. Write to `<state>.tmp` via `python3 -c "import json; json.dump(state, open('<path>.tmp', 'w'), indent=2)"`.
3. `mv <path>.tmp <path>` (atomic rename — never partial-writes the canonical file).
4. Confirm size with `wc -c <path>`; if > 50 KB, externalize large `data.*` fields to dedicated files under `attachments/<run>/` and store only paths in state.

### Externalization rules (proactive context preservation)

Before context pressure kicks in, externalize aggressively:
- Anything > 2 KB of structured output (CSV samples, query results, file diffs) → write immediately to `attachments/<run>/<scenario>/` and reference by path in state. Do NOT keep the raw text in conversation.
- For inspecting files already on disk: use `wc -l`, `head -20`, `tail -20`, or `sed -n '<a>,<b>p'` instead of full `cat`.
- For `gh pr diff <n>` larger than ~200 lines: run `gh pr diff <n> --name-only` first to triage, then read changed files individually only when needed for the Solution Summary (step 3) or regression planning (step 5).
- Comparison matrices, regression results, OWASP scan tables → always to disk; never kept in conversation prose.

### Resume protocol

On EVERY skill invocation:
1. Compute the state file path for the input TC key. Look for both canonical and pre-canonical paths.
2. If a state file exists:
   - Read it.
   - If `status: completed` → tell the user "previous run for TC-XX completed at <timestamp>. View summary or start a new run?" Default: show summary.
   - If `status: in-progress` → tell the user "Estado previo encontrado para TC-XX (last updated <timestamp>, último paso completado <N>/10). ¿Resumir desde el paso <N+1>?" Default: resume.
3. If resume:
   - Load all `data.*` fields into working memory.
   - Skip steps already in `completedSteps`.
   - Continue from `currentStep`.
   - Re-verify any access tokens that may have expired (sf CLI session, safesql profile reachability).
4. If start-fresh (user explicitly opts out):
   - Archive the old state to `<state>.archived-<ISO-timestamp>.json`.
   - Start from step 1 with a fresh state file.

### Cleanup on success

When step 11 (write testrun + handoff) completes successfully:
- Set `status: completed` in the state file.
- Persist final final state at `attachments/tr-<NN>-tc-<NN>/.skill-state-completed.json` (don't delete — useful for retrospectives and audit).
- Include a line in the final summary: "Estado preservado en `<path>`. Re-invocable para regenerar la salida sin re-ejecutar."

### Context-pressure heuristics

I don't have direct access to context size, but these signals indicate time to externalize aggressively and force-save state:
- A tool result returns "Output too large" or is truncated.
- > 50 tool calls without compaction in the conversation.
- A previous response truncated unexpectedly.
- The user mentions "se está acabando el contexto", "context running low", or similar.

When any of these fires:
1. Force-save state with the current progress.
2. Stop generating new conversation output beyond a 2–3 line handoff.
3. Tell the user: "Estado guardado en `<path>`. Si el contexto se compacta, re-invoca `/qa-test-executor <TC-KEY>` y resumiré desde el paso <currentStep>."
4. Stop. Do not continue execution in the current turn.

### Cross-conversation handoff (out of scope but worth noting)

This state file is for within-conversation recovery after harness compaction. For cross-conversation handoff (a coworker continues your QA tomorrow), the harness's auto-memory at `~/.claude/projects/.../memory/MEMORY.md` is the right channel — but that is NOT this skill's responsibility. Persisting the state file at the canonical attachments path is enough for in-session resume and for a future invocation to pick up the same TC key on the same machine.
