# Design: IM-768 Backfill historical analytics progressively

## Technical Approach

Add a local operator runner in `veevart-analytics/scripts/backfill-manual-analytics-runs.cjs`. It remains a Node/CommonJS script like the existing operational scripts, but adds AWS Step Functions polling through `@aws-sdk/client-sfn`. Default behavior is strict sequential execution: one manual-runs API call, wait for its execution ARN to become terminal through `DescribeExecution`, then continue.

## Architecture Decisions

| Decision | Choice | Alternatives | Rationale |
|---|---|---|---|
| Runtime format | CommonJS `.cjs` script | TypeScript/ts-node script | Existing scripts are `.cjs`; easiest operator execution. |
| Period input | `--start-date`, `--end-date`, `--order newest-first|oldest-first` | Month-only flags | User wants date inputs and newest-first backfill for recent data first. |
| Execution model | Strict sequential by default | Fire-and-forget or concurrent starts | Prevents overlapping org/month workloads and protects Salesforce/AWS. |
| Wait mechanism | AWS SFN `DescribeExecution` | API status endpoint | User requested AWS credentials and Step Functions polling. |
| Progress store | Local JSON resume file | Production DB schema | Matches first-version scope and supports pause/resume. |
| Secret handling | API key env var + AWS default provider chain/profile | CLI secrets | Avoids shell history/progress leakage. |

## Data Flow

    org_ids_copyable.js ─→ extract/dedupe org IDs ─→ derive monthly periods
             │                         │               order newest/oldest
             └──────────────→ plan month × org-batch work items
                                      │
                               resume-file filter
                                      │
                      POST manual-runs → executionArn
                                      │
                   DescribeExecution poll until terminal
                                      │
                    progress JSON update → next work item

## File Changes

| File | Action | Description |
|---|---|---|
| `veevart-analytics/scripts/backfill-manual-analytics-runs.cjs` | Create | CLI parser, validators, planner, sequential executor, SFN waiter, progress persistence. |
| `veevart-analytics/scripts/backfill-manual-analytics-runs.spec.cjs` | Create | Jest tests importing exported helpers and mocked request/SFN/sleep functions. |
| `veevart-analytics/package.json` | Modify | Add `@aws-sdk/client-sfn` if needed and optional script aliases. |
| `README.md` | Modify | Document date/order flags, AWS credentials/profile, dry-run, resume, and prod write policy. |

## Interfaces / Contracts

CLI flags: `--start-date`, `--end-date`, `--order newest-first|oldest-first`, `--org-file`, `--org-batch-size`, `--delay-between-runs`, `--dry-run`, `--resume-file`, `--aws-region`, `--aws-profile`, `--poll-interval-ms`, `--execution-timeout-ms`, `--failure-policy stop|continue`. The endpoint is fixed to `https://dcaxoa4js4.execute-api.us-east-1.amazonaws.com/prod/analytics/manual-runs`. The non-dry-run API key MUST be supplied via `MANUAL_EXTRACTION_API_KEY` and sent as `x-api-key`.

Progress record shape:

```js
{
  id: 'YYYY-MM::batch-0001',
  period: { periodKey: 'YYYY-MM', periodStart: 'YYYY-MM-DD', periodEnd: 'YYYY-MM-DD' },
  orgBatch: { index: 1, size: 10, hash: 'sha256...' },
  executionArn: 'arn:aws:states:...',
  status: 'planned|started|running|succeeded|failed|timed_out|aborted',
  startedAt: 'ISO',
  stoppedAt: 'ISO',
  pollCount: 12,
  failure: { message: '...', statusCode: 500, cause: '...' }
}
```

The API request builder remains isolated because the exact manual-runs payload must be confirmed before implementation.

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit | Date validation, month derivation, newest/oldest order | Pure helper Jest tests. |
| Unit | Org extraction/dedupe, batching, resume filtering | Temp file and pure helper tests. |
| Unit | Sequential start/wait behavior | Mock `requestFn`, `describeExecutionFn`, and `sleepFn`; assert second start waits for terminal first. |
| Unit | Timeout/failure policy and progress serialization | Mock terminal statuses and timeout. |
| Unit | Secret redaction | Tests with sentinel API/AWS secret values. |
| Integration-lite | CLI dry-run exits successfully | Spawn Node process against temp org/resume files. |

## Migration / Rollout

No migration required. Rollout is script-only. Real execution against the prod API Gateway endpoint is a shared-environment write and requires explicit command confirmation. AWS credentials must have `states:DescribeExecution` for returned execution ARNs.

## Open Questions

- [ ] Confirm whether default `--end-date` should be today (`2026-05-26`) or the latest closed month for production backfills.
- [ ] Confirm failure policy default: recommended `stop` on failed/timed-out/aborted execution.
