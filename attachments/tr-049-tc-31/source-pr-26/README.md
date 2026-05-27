# VeevartAnalytics

`VeevartAnalytics` is the AWS backend for KPI extraction, normalization, storage, orchestration, and Salesforce publishing for the KPI Automation initiative.

This repository was bootstrapped from `ServerlessAppTemplate` and is the implementation home for Jira epic [IM-505](https://veevart.atlassian.net/browse/IM-505).

## Scope

- Run monthly KPI extractions for subscriber Salesforce orgs.
- Support manual reruns and backfills.
- Store raw source rows, raw metric rows, normalized facts, schedules, and audit data in AWS-managed persistence.
- Publish monthly `Marketing_Metrics__c` records into the Veevart hub org.
- Orchestrate the flow with `EventBridge` and `Step Functions Standard`.

## Repository Layout

- `veevart-analytics/`
  Main NestJS service and AWS SAM infrastructure.
- `.github/workflows/`
  CI/CD pipelines copied from the serverless template and adapted for this service.

## Current Status

This is the initial foundation scaffold for story `IM-507`.

The first implementation phase focuses on:

- repository creation
- CI/CD baseline
- service bootstrap
- OpenSpec migration
- branch/worktree setup for follow-on stories

## Development

At the monorepo root:

```sh
pnpm install
pnpm build
pnpm test
pnpm lint
```

Inside the service package:

```sh
cd veevart-analytics
pnpm build
pnpm test
pnpm lint
```

## Related Jira

- Epic [IM-505](https://veevart.atlassian.net/browse/IM-505): KPI automation phase 1 engine and sync
- Epic [IM-506](https://veevart.atlassian.net/browse/IM-506): KPI automation phase 2 scale and expansion

## Manual Analytics Runs

`POST /analytics/manual-runs` starts the existing monthly KPI extraction Step Functions workflow asynchronously for an explicit date range and target scope. The endpoint is intended for approved backfills or reruns only.

Required deployment configuration:

- `ManualExtractionApiKeySecretArn` — Secrets Manager secret containing the accepted `x-api-key` value. The secret may be a plain string or JSON with `apiKey`, `API_KEY`, `x-api-key`, or `manualExtractionApiKey`.
- The API Lambda receives `MONTHLY_KPI_EXTRACTION_STATE_MACHINE_ARN` from the SAM stack and has `states:StartExecution` permission for that state machine.

Example single-account request:

```http
POST /analytics/manual-runs
x-api-key: <manual extraction API key>
content-type: application/json
```

```json
{
  "periodStart": "2026-03-01",
  "periodEnd": "2026-03-31",
  "subscriberOrgId": "00D5e000005BCc7EAG",
  "accountId": "0015w00002TilynAAB",
  "accountName": "Veevart Developer Staging",
  "reason": "Manual March backfill"
}
```

You can also target multiple subscriber orgs and let the workflow resolve matching destination accounts from VeevartHub:

```json
{
  "periodStart": "2026-03-01",
  "periodEnd": "2026-03-31",
  "subscriberOrgIds": [
    "00D5e000005BCc7EAG",
    "00D000000000001AAA"
  ],
  "reason": "Manual March backfill"
}
```

Provide exactly one target-scope mode per request: `subscriberOrgId` + `accountId`, `destinationAccounts[]`, or `subscriberOrgIds[]`. Salesforce IDs must be 15 or 18 alphanumeric characters, and `subscriberOrgIds[]` is capped at 500 entries to keep Step Functions input below service limits. Successful calls return HTTP `202` with the Step Functions `executionArn` and submitted scope. Manual runs preserve the explicit date range and provided scope; scheduled monthly runs continue to use the previous closed month and all eligible Hub accounts.

> Safety: calling this endpoint against a shared environment can write to analytics Postgres and VeevartHub. Before any shared-environment invocation, request explicit confirmation for the exact command, target environment, org/account scope, side effects, and rollback/verification plan.


### Historical Backfill Runner (IM-768)

Use `veevart-analytics/scripts/backfill-manual-analytics-runs.cjs` for controlled historical backfills. The runner calls the production manual-runs endpoint one calendar month and one org batch at a time, records local progress, and waits for each returned Step Functions execution to reach a terminal status before starting the next work item.

Fixed endpoint used by the runner:

```txt
https://dcaxoa4js4.execute-api.us-east-1.amazonaws.com/prod/analytics/manual-runs
```

Operator checklist:

1. Confirm the exact command, date range, target org source, side effects, and rollback/verification plan before any non-dry-run shared-environment call.
2. Export the approved API key only through `MANUAL_EXTRACTION_API_KEY`; do not pass it as a CLI flag.
3. Configure AWS credentials/profile with `states:DescribeExecution` access to the returned execution ARNs.
4. Choose exactly one target org source: `--org-file` for large lists, or `--subscriber-org-ids` / repeated `--subscriber-org-id` for direct IDs.
5. Run `--dry-run` first and review counts before removing `--dry-run`.
6. Keep the generated resume/progress file; reruns skip `SUCCEEDED` work items.

Dry-run example with an org file:

```sh
pnpm --dir veevart-analytics backfill:manual-runs -- \
  --start-date 2016-01-01 \
  --end-date 2026-05-26 \
  --order newest-first \
  --org-file /Users/joseangarita/Developer/tmp/sf-report-org-ids/org_ids_copyable.js \
  --org-batch-size 10 \
  --resume-file ./backfill-manual-analytics-runs.progress.json \
  --dry-run
```

Dry-run example with direct subscriber org IDs:

```sh
pnpm --dir veevart-analytics backfill:manual-runs -- \
  --start-date 2026-05-01 \
  --end-date 2026-05-31 \
  --order newest-first \
  --subscriber-org-ids '["00D000000000000AAA", "00D000000000001AAA"]' \
  --org-batch-size 2 \
  --resume-file ./backfill-manual-analytics-runs.progress.json \
  --dry-run
```

For direct input, `--subscriber-org-ids` accepts a JSON-style string array, comma-separated values, or whitespace-separated values. You can also repeat `--subscriber-org-id` for one or more values. Do not combine direct IDs with `--org-file` in the same command.

Non-dry-run shape, after explicit approval for the exact command:

```sh
export MANUAL_EXTRACTION_API_KEY='<approved manual extraction API key>'
export AWS_PROFILE='<profile with states:DescribeExecution access>'

pnpm --dir veevart-analytics backfill:manual-runs -- \
  --start-date 2016-01-01 \
  --end-date 2026-05-26 \
  --order newest-first \
  --org-file /Users/joseangarita/Developer/tmp/sf-report-org-ids/org_ids_copyable.js \
  --org-batch-size 10 \
  --poll-interval-ms 30000 \
  --execution-timeout-ms 21600000 \
  --failure-policy stop \
  --resume-file ./backfill-manual-analytics-runs.progress.json
```

The runner never logs or persists API keys, AWS credentials, or raw org IDs in the progress file. It still sends `subscriberOrgIds[]` in the request body because the endpoint requires that target scope.

## Replay Identity Migrations

Migrations `0007` and `0008` align deployed unique indexes with runtime rerun behavior so manual replays can replace prior raw source rows and metric facts for the same business identity. Fresh schema migration `0001` declares the same replay-safe identities for new environments.
