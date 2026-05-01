# TestCase Generator

Generate test case YAML files compatible with TestManager for GitHub.

Agent identity for this skill: `codex` - direct, technical, concise, and QA-focused.

## Trigger

When user asks to create test cases, generate tests, add QA cases, or mentions "test case" / "caso de prueba" in the context of this project.

## Schema

Every `.testcase.yml` file MUST follow this exact structure. The **default format is `gherkin`** (BDD with Given/When/Then scenarios). Only use `format: steps` if the user explicitly requests it.

### Gherkin format (DEFAULT)

```yaml
schemaVersion: "1.0"

id: "<uuid-v4>"
key: "<PREFIX>-<NNN>"   # e.g. TC-001, TC-042
title: "<descriptive title>"
description: |
  <optional multi-line description>

type: <functional|regression|smoke|integration|e2e|performance|security|accessibility>
priority: <low|medium|high|critical>
status: <draft|active|deprecated|archived>

preconditions:
  - "<condition 1>"
  - "<condition 2>"

format: gherkin
scenarios:
  - title: "<scenario title>"
    tags:
      - <scenario-tag>
    given:
      - "<initial context / setup>"
      - "<another precondition state>"
    when:
      - "<action the user performs>"
      - "<another action>"
    then:
      - "<expected outcome>"
      - "<another expected outcome>"

tags:
  - <tag1>
  - <tag2>

estimatedDuration: <minutes>

metadata:
  createdBy: "<author>"
  createdAt: "<ISO-8601>"
  updatedBy: "<author>"
  updatedAt: "<ISO-8601>"
  version: 1
```

### Steps format (only when user explicitly requests it)

Use this format ONLY if the user says "use steps format", "formato steps", "sin gherkin", or similar explicit indication.

```yaml
# Same header fields as above, then:

format: steps
steps:
  - order: 1
    action: "<what the tester does>"
    expected: "<what should happen>"
  - order: 2
    action: "<next action>"
    expected: "<expected result>"

# Same footer fields (tags, estimatedDuration, metadata)
```

## Rules

1. **File naming**: `<feature-slug>.testcase.yml` — name after the FEATURE being tested (e.g. `login.testcase.yml`, `create-product.testcase.yml`), NOT after a specific scenario. Lowercase, hyphens, no spaces
2. **File location**: Always inside `test-cases/` or a subfolder of it (organized by feature/module)
3. **Key format**: Read `.testmanager.yml` for the prefix (default: `TC`). Scan existing files to determine the next sequential number. NEVER duplicate keys.
4. **ID**: Always generate a fresh UUID v4
5. **Format**: Default to `gherkin`. Only use `steps` if the user explicitly asks for it.
6. **Scenarios (gherkin)**: Minimum 1 scenario. Each scenario MUST have non-empty `title`, at least 1 `given`, 1 `when`, and 1 `then`. Be specific — avoid vague statements like "the system works correctly"
7. **Steps (steps format)**: Minimum 1 step. Each step MUST have `action` and `expected`. Be specific — avoid vague actions like "verify it works"
8. **Tags**: Use lowercase, hyphenated tags. Include the module/feature name as a tag
9. **Status**: New test cases should be `active` unless user specifies otherwise
10. **Priority**: Default to `medium` unless user specifies
11. **Type**: Default to `functional` unless the context suggests otherwise
12. **Preconditions**: Include setup steps the tester needs BEFORE starting (logged in, data exists, etc.)
13. **estimatedDuration**: Estimate in minutes how long a manual execution would take
14. **metadata.createdBy**: Use `codex` as default author

## Gherkin Writing Guidelines

Write scenarios in clear, behavior-driven language:

- **Given** — describes the initial context or state (what is already true)
- **When** — describes the action or event the user performs
- **Then** — describes the expected outcome or observable result

Tips:
- Keep each step atomic — one action or assertion per line
- Use business language, not implementation details (say "the user is logged in" not "the session token is valid")
- Scenario `tags` are optional but useful for filtering (e.g. `happy-path`, `negative`, `edge-case`)

## Scenario Grouping Strategy

**A single test case file groups ALL scenarios that test the same feature or user action.** Do NOT create a separate file per scenario. Think of a test case as a FEATURE under test, and scenarios as the VARIATIONS of that feature.

### Grouping rules

| Scenarios that... | Go in... |
|---|---|
| Test variations of the SAME action (login valid, login invalid, login locked account) | **ONE test case file** with multiple scenarios |
| Test the SAME form/page/flow with different inputs | **ONE test case file** with multiple scenarios |
| Test DIFFERENT features that share a module (login vs password reset vs registration) | **SEPARATE test case files** |
| Test completely unrelated functionality | **SEPARATE test case files** |

### How to decide

Ask yourself: "Are these scenarios testing the SAME user action/feature with different inputs or conditions?" If yes → same file. If no → separate files.

**CORRECT** — one file `login.testcase.yml` with scenarios:
- "Successful login with valid credentials" (happy path)
- "Login fails with incorrect password" (negative)
- "Login fails with non-existent email" (negative)
- "Account locks after 5 failed attempts" (edge case)
- "Login with expired password prompts reset" (edge case)

**WRONG** — five separate files:
- `login-valid-credentials.testcase.yml` (1 scenario)
- `login-invalid-password.testcase.yml` (1 scenario)
- `login-non-existent-email.testcase.yml` (1 scenario)
- `login-account-lockout.testcase.yml` (1 scenario)
- `login-expired-password.testcase.yml` (1 scenario)

### When to split into separate files

- Different features even if same module: "Login" vs "Password Reset" vs "Registration" → 3 files
- Different CRUD operations: "Create Product" vs "Edit Product" vs "Delete Product" → 3 files
- Different user roles with entirely different flows: "Admin Dashboard" vs "User Dashboard" → 2 files

## Folder Organization

Organize test cases into folders by feature/module:

```
test-cases/
├── auth/                    # Authentication & authorization
├── inventory/               # Inventory management
├── sales/                   # Sales & orders
├── payments/                # Payment processing
├── reporting/               # Reports & analytics
├── integrations/            # Third-party integrations
│   ├── shopify/
│   └── salesforce/
├── ui/                      # UI/UX specific tests
└── api/                     # API endpoint tests
```

Create the subfolder if it doesn't exist. Ask the user which module/feature the test case belongs to if not obvious.

## Bulk Generation

When asked to generate multiple test cases:

1. Ask for the feature/module context
2. **Identify the distinct features/actions** to test (e.g. login, registration, password reset)
3. **For each feature, create ONE test case file** with multiple scenarios covering:
   - **Happy path**: Normal successful flow
   - **Negative cases**: Invalid inputs, unauthorized access, missing data
   - **Edge cases**: Boundary values, empty states, max limits
   - **Error handling**: Network failures, timeouts, concurrent access
4. Use sequential keys (TC-001, TC-002, etc.) continuing from the highest existing key — one key per FILE, not per scenario
5. Group related files in the same subfolder
6. Apply appropriate tags consistently

**Example**: "generate test cases for the auth module" should produce ~3-4 FILES (login, registration, password-reset, session-management), each with 3-6 SCENARIOS inside. NOT 15+ individual files with 1 scenario each.

## Example Output

For "generate test cases for user login":

Notice how ONE file groups ALL login-related scenarios — happy path, negative, and edge cases. This is a single feature (login) tested from multiple angles.

**File**: `test-cases/auth/login.testcase.yml`
```yaml
schemaVersion: "1.0"

id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
key: "TC-001"
title: "User Login"
description: |
  Covers all login scenarios: valid credentials, invalid inputs,
  account lockout, and session handling.

type: functional
priority: high
status: active

preconditions:
  - "User has access to the login page"
  - "Test accounts exist in the system"

format: gherkin
scenarios:
  - title: "Successful login with valid email and password"
    tags:
      - happy-path
    given:
      - "the user is on the login page"
      - "a registered account exists with email user@veevart.com"
    when:
      - "the user enters their registered email address"
      - "the user enters the correct password"
      - "the user clicks the Sign In button"
    then:
      - "the user is redirected to the dashboard"
      - "a welcome message displays the user's name"
      - "the session remains active for the configured timeout period"

  - title: "Login fails with incorrect password"
    tags:
      - negative
    given:
      - "the user is on the login page"
      - "a registered account exists with email user@veevart.com"
    when:
      - "the user enters their registered email address"
      - "the user enters an incorrect password"
      - "the user clicks the Sign In button"
    then:
      - "an error message is displayed: Invalid email or password"
      - "the user remains on the login page"
      - "the password field is cleared"

  - title: "Login fails with non-existent email"
    tags:
      - negative
    given:
      - "the user is on the login page"
    when:
      - "the user enters an email that is not registered"
      - "the user enters any password"
      - "the user clicks the Sign In button"
    then:
      - "an error message is displayed: Invalid email or password"
      - "the error message does not reveal whether the email exists"

  - title: "Account locks after 5 consecutive failed attempts"
    tags:
      - edge-case
      - security
    given:
      - "the user is on the login page"
      - "a registered account exists with email user@veevart.com"
      - "the account has had 4 consecutive failed login attempts"
    when:
      - "the user enters the registered email"
      - "the user enters an incorrect password for the 5th time"
      - "the user clicks the Sign In button"
    then:
      - "the account is temporarily locked"
      - "a message is displayed: Account locked. Try again in 30 minutes."
      - "an email notification is sent to the account owner"

tags:
  - auth
  - login
  - smoke

estimatedDuration: 5

metadata:
  createdBy: "codex"
  createdAt: "2026-03-28T10:00:00Z"
  updatedBy: "codex"
  updatedAt: "2026-03-28T10:00:00Z"
  version: 1
```

## Validation Checklist

Before writing any file, verify:
- [ ] `id` is a valid UUID v4
- [ ] `key` is unique (not used by any existing file)
- [ ] `format` is set (defaults to `gherkin`)
- [ ] **If gherkin**: `scenarios` has at least 1 entry, each with non-empty `title`, `given`, `when`, `then`
- [ ] **If steps**: `steps` has at least 1 entry, each with non-empty `action` and `expected`
- [ ] `metadata.createdBy` and `updatedBy` are non-empty
- [ ] `metadata.createdAt` and `updatedAt` are valid ISO-8601
- [ ] File is inside `test-cases/` or a subfolder
- [ ] Filename ends with `.testcase.yml`
- [ ] YAML is valid and parseable
