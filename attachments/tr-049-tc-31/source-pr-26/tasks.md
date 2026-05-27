# Tasks: IM-768 Backfill historical analytics progressively

## Phase 1: Contract and Foundation

- [x] 1.1 Build the script request builder against the confirmed endpoint `https://dcaxoa4js4.execute-api.us-east-1.amazonaws.com/prod/analytics/manual-runs` with `x-api-key`, `periodStart`, `periodEnd`, and `subscriberOrgIds[]`; read `executionArn` from the HTTP 202 response.
- [x] 1.2 Use the existing `@aws-sdk/client-sfn` dependency for `DescribeExecution`; no new SFN dependency is needed on current `main`.
- [x] 1.3 Create `veevart-analytics/scripts/backfill-manual-analytics-runs.cjs` with guarded `main()` and exported helpers.
- [x] 1.4 Implement CLI parsing/validation for start/end date, order, org file, batch size, delay, dry run, resume file, API URL/key env, AWS region/profile, poll interval, timeout, and failure policy.
- [x] 1.6 Define safe defaults: required API key env var `MANUAL_EXTRACTION_API_KEY`, fixed endpoint URL, failure policy `stop`, newest-first option, progress file path, poll interval, and execution timeout.
- [x] 1.5 Add/keep tests or fixtures that protect the confirmed endpoint contract, especially `subscriberOrgIds[]` batching limit and `executionArn` response handling.

## Phase 2: Planning and Progress

- [x] 2.1 Implement org-file loading/extraction/deduplication without logging raw org IDs.
- [x] 2.6 Support direct subscriber org IDs via CLI as an alternative to `--org-file`, including validation, dedupe, and mutually exclusive source checks.
- [x] 2.2 Implement inclusive date-to-month generation and `newest-first`/`oldest-first` ordering.
- [x] 2.3 Implement org batching and work item IDs keyed by `periodKey` plus batch index/hash.
- [x] 2.4 Implement local JSON progress loading/writing with execution ARN, SFN terminal status, timestamps, poll count, and secret-free serialization.
- [x] 2.5 Implement resume filtering so `SUCCEEDED` items are skipped and failed/incomplete items follow retry policy.

## Phase 3: Sequential Execution and Waiting

- [x] 3.1 Implement dry-run output that reports unique org count, ordered periods, and planned month/batch totals without network/AWS calls.
- [x] 3.2 Implement request builder for one month/batch payload (`periodStart`, `periodEnd`, `subscriberOrgIds[]`, `reason`) using `MANUAL_EXTRACTION_API_KEY` as the `x-api-key` header; fail clearly before network calls when the env var is missing, and on non-2xx or missing ARN.
- [x] 3.3 Implement AWS Step Functions client creation from `--aws-region`/`--aws-profile` and default AWS credential chain; prefer inferring region from returned `executionArn` when `--aws-region` is omitted.
- [x] 3.4 Implement `DescribeExecution` polling until `SUCCEEDED`, `FAILED`, `TIMED_OUT`, or `ABORTED`, with timeout handling.
- [x] 3.5 Implement strict sequential loop: do not start the next work item until the current execution reaches a terminal status and progress is written.
- [x] 3.6 Ensure API key/AWS credentials are never accepted as CLI values and never logged or persisted.

## Phase 4: Tests and Documentation

- [x] 4.1 Add Jest tests for duplicate org dry-run counts, date/month ordering, monthly-only planning, invalid date/order failures, and resume skips.
- [x] 4.2 Add Jest tests proving the second API call is not made until the first execution reaches terminal `DescribeExecution` status.
- [x] 4.3 Add Jest tests for terminal failure/timeout policy, progress recording, API response handling, and secret redaction.
- [x] 4.4 Add package script aliases if useful for focused test and runner execution.
- [x] 4.5 Update `README.md` with dry-run-first usage, `MANUAL_EXTRACTION_API_KEY` requirement, fixed endpoint URL, AWS credentials/profile/region or ARN-region inference, newest-first examples, resume examples, and shared-environment write warning.
- [x] 4.7 Add an operator runbook section: a short copy/paste-safe checklist and example commands for dry-run and real execution, using placeholders instead of real API keys or raw org IDs, and do not execute real commands during validation.
- [x] 4.6 Run targeted validation: `node --check`, `pnpm --dir veevart-analytics test:backfill:manual-runs`, safe dry-run, `pnpm --dir veevart-analytics build`, full `pnpm --dir veevart-analytics test --runInBand`, and `git diff --check`.
