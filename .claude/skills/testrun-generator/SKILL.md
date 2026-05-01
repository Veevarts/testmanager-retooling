# TestRun Generator

Generate test run YAML files compatible with TestManager for GitHub. Test runs record the execution results of test cases.

Agent identity for this skill: `codex` - direct, technical, concise, and QA-focused.

## Trigger

When user asks to create test runs, execute tests, run tests, record test execution, or mentions "test run" / "ejecucion de pruebas".

## Schema

Every `.testrun.yml` file MUST follow this exact structure:

```yaml
schemaVersion: "1.0"

id: "<uuid-v4>"
key: "TR-<NNN>"
title: "<descriptive run title>"
status: <planned|in-progress|completed|aborted>

environment:
  name: "<env name>"
  url: "<optional base URL>"
  browser: "<optional>"
  os: "<optional>"
  buildVersion: "<optional>"
  commitSha: "<optional>"

results:
  - testCaseId: "<uuid of test case>"
    testCaseKey: "TC-001"
    testCaseTitle: "<title>"
    testCaseFilePath: "test-cases/<module>/<file>.testcase.yml"
    status: <passed|failed|blocked|skipped|not-run>
    executedAt: "<ISO-8601 or empty>"
    duration: <minutes or 0>
    stepResults:
      # See "Step Results by Format" below
    notes: ""
    attachments: []
    defects: []

summary:
  total: <number>
  passed: <number>
  failed: <number>
  blocked: <number>
  skipped: <number>
  notRun: <number>
  passRate: <0-100>

history: []

metadata:
  createdBy: "<author>"
  createdAt: "<ISO-8601>"
  updatedBy: "<author>"
  updatedAt: "<ISO-8601>"
```

## Step Results by Format

When generating stepResults, read the test case's `format` field to determine the structure.

### Gherkin format (default — `format: gherkin`)

For each scenario in the test case, generate one stepResult per Given/When/Then step. Include `phase` and `text` fields:

```yaml
stepResults:
  # From scenario "Successful login with valid email and password"
  - order: 1
    status: not-run
    actual: ""
    phase: given
    text: "the user is on the login page"
    attachments: []
  - order: 2
    status: not-run
    actual: ""
    phase: given
    text: "a registered account exists with email user@veevart.com"
    attachments: []
  - order: 3
    status: not-run
    actual: ""
    phase: when
    text: "the user enters their registered email address"
    attachments: []
  - order: 4
    status: not-run
    actual: ""
    phase: when
    text: "the user enters the correct password"
    attachments: []
  - order: 5
    status: not-run
    actual: ""
    phase: then
    text: "the user is redirected to the dashboard"
    attachments: []
```

**Order of flattening**: For each scenario, emit all `given` steps first, then `when`, then `then`. If the test case has multiple scenarios, continue the order numbering sequentially across scenarios.

### Steps format (`format: steps`)

For each step in the test case, generate a stepResult with `phase: action`, `text` matching the action, and `expected`:

```yaml
stepResults:
  - order: 1
    status: not-run
    actual: ""
    phase: action
    text: "Enter registered email address in the email field"
    expected: "Email is accepted and displayed in the field"
    attachments: []
  - order: 2
    status: not-run
    actual: ""
    phase: action
    text: "Enter correct password in the password field"
    expected: "Password is masked with dots/asterisks"
    attachments: []
```

## Rules

1. **File naming**: `<key>-<date>.testrun.yml` — e.g. `tr-001-2026-03-27.testrun.yml`
2. **File location**:
   - From a test plan → `test-runs/<plan-slug>/<filename>`
   - Standalone → `test-runs/<YYYY-MM-DD>/<filename>`
3. **Key format**: `TR-<NNN>`. Scan existing runs to determine next number. NEVER duplicate.
4. **ID**: Always generate a fresh UUID v4
5. **Status**: New runs should be `planned`
6. **Results**: One entry per test case. Each entry has `stepResults` matching the test case's steps/scenarios.
7. **Step results**: Initialize ALL with status `not-run` and empty `actual`. Read the test case to determine the correct format:
   - **Gherkin**: Flatten all scenarios' given/when/then into sequential stepResults with `phase` and `text`
   - **Steps**: One stepResult per step with `phase: action`, `text`, and `expected`
8. **Summary**: Calculate from results. For new runs: total = number of test cases, notRun = total, everything else = 0, passRate = 0.
9. **History**: Empty array for new runs. Entries are added when status changes.

## Creating from Test Plan

When user references a test plan:

1. Read the `.testplan.yml` file
2. For each entry in the plan, read the referenced `.testcase.yml` to get format and steps/scenarios
3. Generate a run with all plan entries as results, building stepResults according to each test case's format
4. Title format: `"Run <plan-key>: <plan-title>"`
5. Save in `test-runs/<plan-slug>/`

## Creating Standalone

When user wants a quick run without a plan:

1. Ask which test cases to include (by module, tag, or specific cases)
2. Scan and read each selected `.testcase.yml`
3. Generate the run with stepResults matching each test case's format
4. Save in `test-runs/<YYYY-MM-DD>/`

## Recording Results

When user wants to record execution results on an EXISTING run:

1. Read the current `.testrun.yml`
2. Update the specified test case results:
   - Set `status` on each stepResult (passed/failed/blocked/skipped)
   - Fill `actual` field with what actually happened (especially for failures)
   - Set `executedAt` to current timestamp
   - Set `duration` if provided
3. Derive test case status from step results:
   - ANY step failed → test case `failed`
   - ANY step blocked (none failed) → test case `blocked`
   - ANY step skipped (none failed/blocked) → test case `skipped`
   - ALL steps passed → test case `passed`
4. Recalculate `summary` (total, passed, failed, etc.)
5. Update `metadata.updatedAt`
6. Add history entry if status changed

## History Entry Format

```yaml
history:
  - action: "reopened"         # or "completed", "aborted", "started"
    timestamp: "<ISO-8601>"
    user: "codex"
    from: "completed"
    to: "in-progress"
    reason: "Found missed step in TC-003"
```

## Example Output

**File**: `test-runs/2026-03-28/tr-005-2026-03-28.testrun.yml`
```yaml
schemaVersion: "1.0"

id: "c3d4e5f6-a7b8-9012-cdef-123456789012"
key: "TR-005"
title: "Smoke test - Auth module"
status: planned

environment:
  name: "staging"
  url: "https://staging.veevart.com"
  browser: "Chrome 120"
  os: "macOS"

results:
  - testCaseId: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    testCaseKey: "TC-001"
    testCaseTitle: "Login with valid credentials"
    testCaseFilePath: "test-cases/auth/login-valid-credentials.testcase.yml"
    status: not-run
    executedAt: ""
    duration: 0
    stepResults:
      - order: 1
        status: not-run
        actual: ""
        phase: given
        text: "the user is on the login page"
        attachments: []
      - order: 2
        status: not-run
        actual: ""
        phase: given
        text: "a registered account exists with email user@veevart.com"
        attachments: []
      - order: 3
        status: not-run
        actual: ""
        phase: when
        text: "the user enters their registered email address"
        attachments: []
      - order: 4
        status: not-run
        actual: ""
        phase: when
        text: "the user enters the correct password"
        attachments: []
      - order: 5
        status: not-run
        actual: ""
        phase: when
        text: "the user clicks the Sign In button"
        attachments: []
      - order: 6
        status: not-run
        actual: ""
        phase: then
        text: "the user is redirected to the dashboard"
        attachments: []
      - order: 7
        status: not-run
        actual: ""
        phase: then
        text: "a welcome message displays the user's name"
        attachments: []
      - order: 8
        status: not-run
        actual: ""
        phase: then
        text: "the session remains active for the configured timeout period"
        attachments: []
    notes: ""
    attachments: []
    defects: []

summary:
  total: 1
  passed: 0
  failed: 0
  blocked: 0
  skipped: 0
  notRun: 1
  passRate: 0

history: []

metadata:
  createdBy: "codex"
  createdAt: "2026-03-28T10:00:00Z"
  updatedBy: "codex"
  updatedAt: "2026-03-28T10:00:00Z"
```

## Validation Checklist

Before writing any file:
- [ ] `id` is a valid UUID v4
- [ ] `key` is unique (TR-NNN not used by existing runs)
- [ ] All results reference REAL existing test cases (verified by reading the files)
- [ ] `stepResults` correctly reflect the test case's format:
  - **Gherkin**: each given/when/then step has `phase` and `text`, order is sequential across scenarios
  - **Steps**: each step has `phase: action`, `text`, and `expected`
- [ ] `summary` numbers add up correctly (total = passed + failed + blocked + skipped + notRun)
- [ ] `passRate` = (passed / total) * 100, rounded
- [ ] File is inside `test-runs/<plan-slug>/` or `test-runs/<date>/`
- [ ] Filename ends with `.testrun.yml`
