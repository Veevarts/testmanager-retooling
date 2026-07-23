# API call transcript — TR-117 v2 (IM-1079 · IC 3.22 v4 · illinois-trainings)

Base: `https://zu76ogw8dg.execute-api.us-east-1.amazonaws.com/dev/api` · Bearer
token from `localStorage['migrationapp.access_token']` of the logged-in
Migration App session (all calls made via `fetch` INSIDE the authenticated
browser context via Playwright — the token never left the browser).
Executed 2026-07-23 ~18:51–18:55 UTC.

Constants: `clientId = cdff34f1-9774-41b0-a6a3-124bc03d11cb` (Test IM cases
Org Tucson workspace) · `orgId = 00DWI00000CIwZi2AL` (illinois-trainings).

## 0 · Preflight — seed check

`GET /implementations/cases` → **200** · **77 cases** · target present:
```json
{"caseId":"ic-3-22-pos-batches","version":4,"name":"Drawer Control Batch & POS Purchase Payment Propagation Batch","category":"CORE_SETUP","defaultOrder":322,"active":true,"feasibility":"hybrid"}
```

## AC2 — batchScope=500 override

### 1. Start run
`POST /implementations/plan-runs`
Body: `{"clientId":"cdff34f1-…","orgId":"00DWI00000CIwZi2AL","caseIds":["ic-3-22-pos-batches"]}`
→ **202**
```json
{"planRunId":"b5e64a86-daaf-4d2b-b893-3a62faf9d71c","orgId":"00DWI00000CIwZi2AL","clientId":"cdff34f1-…","status":"AWAITING_INPUT","startedAt":"2026-07-23T18:51:17.314Z"}
```

### 2. Discover parked input
`GET /implementations/runs/b5e64a86-…` → state `awaiting-input`, step 1
`Run the POS Purchase Payment Propagation batch` parked with:
```json
{"type":"number","key":"batchScope","label":"POS batch scope (whole number of records per chunk)","placeholder":"200","constraints":{"min":1,"max":2000}}
```
Live discovery of input schema — matches EXACTLY what the JSON spec v4 declares.
Step 2 `Run the Cashier Drawer Control batch (manual)` is `pending`.

### 3. Submit operator input
First attempt with `{batchScope: 500}` (number) → **400** `operatorInputs must
be an object of at most 50 string values, each ≤255 characters`. Retry with
`{batchScope: '500'}` (string) → **202** `{status: PENDING, remainingInputs: []}`.

**API contract note**: `POST /inputs` expects `operatorInputs` as `{key: string}` even
when the input `type` is `number`. Backend coerces the string.

### 4. Poll until auto-step completes
Cycles observed (5s tick):
- t=0: run `running`, step1 `running`, step2 `pending`
- t=5: run `paused`, step1 `done`, step2 `blocked-human`
- counts: total 2 · done 1 · blocked 1 · running 0 · failed 0

### 5. Attest MANUAL step 2 (Cashier Drawer Control)
`POST /implementations/plan-runs/b5e64a86-…/steps/b7e83a5d-…/b9732433-…/handoff` → **202**
- caseRunId: `b7e83a5d-19a5-477e-b825-39ca2a1b15ed`
- stepRunId (step 2): `b9732433-c04f-4ebd-b220-56c3f813a9ca`
- Body: `{}` — attesting-without-executing (test workspace, per TR-115/TR-116 pattern)

### 6. Final state
counts: total 2 · **done 2** · running 0 · blocked 0 · failed 0

## AC3 — batchScope=200 recommended default

### 1. Start run
`POST /implementations/plan-runs` (same client + org + caseIds)
→ **202** `{"planRunId":"a5dc118c-b1b2-4e91-b44a-cb571ca88462","status":"AWAITING_INPUT","startedAt":"2026-07-23T18:54:01.285Z"}`

### 2. Submit input
`POST /implementations/plan-runs/a5dc118c-…/inputs`
Body: `{"operatorInputs": {"batchScope": "200"}}` → **202** `{status:"PENDING", remainingInputs:[]}`

### 3. Poll (5s tick)
- t=0: run `queued`, step1 `pending`, step2 `pending`
- t=5: run `running`, step1 `running`, step2 `pending`
- t=10: run `paused`, step1 `done`, step2 `blocked-human`

### 4. Attest MANUAL step 2
`POST /implementations/plan-runs/a5dc118c-…/steps/56b23de0-…/fa561c60-…/handoff` → **202**
- caseRunId: `56b23de0-b512-4500-8f3c-3dc16b4c36c2`
- stepRunId (step 2): `fa561c60-6efb-48be-b4ed-ec095acb2fbb`

### 5. Final state
counts: total 2 · **done 2** · running 0 · blocked 0 · failed 0

## POST-verify — illinois-trainings AsyncApexJob

`sf data query --target-org illinois-trainings --query "SELECT Id, ParentJobId,
Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, CreatedDate FROM
AsyncApexJob WHERE ApexClass.Name = 'POSPurchasePaymentPropagationBatch' AND
ApexClass.NamespacePrefix = 'Auctifera' AND CreatedDate = LAST_N_DAYS:1 ORDER
BY CreatedDate DESC LIMIT 10"`

PRE-baseline (captured pre-run 1): **0 rows**.
POST both runs: **4 rows** (2 pairs of parent+child, all Completed, 0 errors).

| Id                  | Parent               | Run  | Timestamp                | Status    | Items | Errors |
|---------------------|----------------------|------|--------------------------|-----------|-------|--------|
| 707WI0000PMHMKvYQP  | 707WI0000PMHLOAYQ5   | AC3  | 2026-07-23T18:54:13Z     | Completed | 1/1   | 0      |
| 707WI0000PMHLOAYQ5  | (root)               | AC3  | 2026-07-23T18:54:05Z     | Completed | 1/1   | 0      |
| 707WI0000PMHCXEYQ5  | 707WI0000PMHO84YQH   | AC2  | 2026-07-23T18:52:17Z     | Completed | 1/1   | 0      |
| 707WI0000PMHO84YQH  | (root)               | AC2  | 2026-07-23T18:52:17Z     | Completed | 1/1   | 0      |

The parent+child structure is Auctifera's internal batch chain (parent
schedules → child processes chunks). Both parents were enqueued directly by
`Database.executeBatch(new Auctifera.POSPurchasePaymentPropagationBatch(),
BATCH_SCOPE)` from the anonymous Apex in each run.

## Observations

- The batchScope difference (500 vs 200) isn't visible via `TotalJobItems` on
  illinois-trainings because the tenant appears to have ≤ 1 record to process
  per run. The AC assertion is "the batch is enqueued in an accepted state" —
  satisfied for both runs (both reached Completed, which is one of the
  accepted states: Holding | Queued | Preparing | Processing | Completed).
- The API `/inputs` endpoint requires string values even when the input `type`
  is `number` — worth documenting for the next IC with typed inputs.
- Cashier Drawer Control step 2 was attested (attesting-without-executing) in
  the test workspace to close the runs, per the TR-115/TR-116 pattern. The
  actual manual UI work was NOT performed — the AC4 evidence for that step
  stays statically-verified (spec declares `kind: MANUAL`).
