# TestPlan Generator

Generate test plan YAML files compatible with TestManager for GitHub.

Agent identity for this skill: `codex` - direct, technical, concise, and QA-focused.

## Trigger

When user asks to create test plans, plan testing, plan a release, QA planning, or mentions "test plan" / "plan de pruebas".

## Schema

Every `.testplan.yml` file MUST follow this exact structure:

```yaml
schemaVersion: "1.0"

id: "<uuid-v4>"
key: "TP-<NNN>"
title: "<descriptive plan title>"
description: |
  <what this plan covers and why>

status: <draft|active|in-progress|completed|archived>

scope:
  milestone: "<version or release name>"
  targetDate: "<YYYY-MM-DD>"
  environment: "<staging|production|development|qa>"
  browser: "<chrome|firefox|safari|all>"

entries:
  - id: "<uuid-v4-of-testcase>"
    key: "TC-001"
    title: "<test case title>"
    filePath: "test-cases/<module>/<file>.testcase.yml"

assignees:
  owner: "<who owns the plan>"
  executor: "<who runs the tests>"
  reviewer: "<who reviews results>"

tags:
  - <tag1>
  - <tag2>

metadata:
  createdBy: "<author>"
  createdAt: "<ISO-8601>"
  updatedBy: "<author>"
  updatedAt: "<ISO-8601>"
  version: 1
```

## Rules

1. **File naming**: `<slug-of-title>.testplan.yml` — lowercase, hyphens
2. **File location**: Always inside `test-plans/`
3. **Key format**: `TP-<NNN>`. Scan existing plans to determine next sequential number. NEVER duplicate keys.
4. **ID**: Always generate a fresh UUID v4
5. **Status**: New plans should be `draft` unless user specifies otherwise
6. **Entries**: Reference EXISTING test cases by their id, key, title, and filePath. ALWAYS scan the repo first to find valid test cases. Never invent test case references.
7. **Scope**: Ask the user for milestone, target date, and environment if not provided
8. **Assignees**: Ask the user for assignees. Default owner to `codex` if not specified.

## Workflow

1. **Scan existing test cases**: Read all `.testcase.yml` files to know what's available
2. **Ask for scope**: Milestone, target date, environment, browser
3. **Select test cases**: Let user choose which test cases to include. Suggest grouping by:
   - Module/folder (all auth tests, all inventory tests)
   - Tags (all smoke tests, all regression tests)
   - Priority (all critical + high priority)
4. **Generate the plan**: Create the `.testplan.yml` with all selected entries
5. **Save**: Write to `test-plans/<slug>.testplan.yml`

## Bulk Selection Helpers

When user says:
- "all smoke tests" → filter test cases by tag `smoke`
- "all auth tests" → filter test cases in `test-cases/auth/`
- "all critical tests" → filter test cases with priority `critical`
- "everything" → include ALL test cases
- "regression suite" → filter by tag `regression` or type `regression`

## Example Output

**File**: `test-plans/release-2.0-regression.testplan.yml`
```yaml
schemaVersion: "1.0"

id: "f1e2d3c4-b5a6-7890-abcd-ef1234567890"
key: "TP-001"
title: "Release 2.0 Regression"
description: |
  Full regression test plan for Release 2.0.
  Covers authentication, inventory, and sales modules.

status: draft

scope:
  milestone: "Release 2.0"
  targetDate: "2026-04-15"
  environment: "staging"
  browser: "chrome"

entries:
  - id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    key: "TC-001"
    title: "Login with valid credentials"
    filePath: "test-cases/auth/login-valid-credentials.testcase.yml"
  - id: "b2c3d4e5-f6a7-8901-bcde-f12345678901"
    key: "TC-002"
    title: "Login with invalid password"
    filePath: "test-cases/auth/login-invalid-password.testcase.yml"

assignees:
  owner: "codex"
  executor: "qa-team"
  reviewer: "tech-lead"

tags:
  - regression
  - release-2.0

metadata:
  createdBy: "codex"
  createdAt: "2026-03-27T10:00:00Z"
  updatedBy: "codex"
  updatedAt: "2026-03-27T10:00:00Z"
  version: 1
```

## Validation Checklist

Before writing any file:
- [ ] `id` is a valid UUID v4
- [ ] `key` is unique (TP-NNN not used by existing plans)
- [ ] All entries reference REAL existing test cases (verified by scanning repo)
- [ ] `metadata.createdBy` and `updatedBy` are non-empty
- [ ] File is inside `test-plans/`
- [ ] Filename ends with `.testplan.yml`
