# API call transcript — TR-122 (IM-1079 · IC 3.22 v6 fully-auto · illinois-trainings)

Base: `https://zu76ogw8dg.execute-api.us-east-1.amazonaws.com/dev/api` · Bearer token from `localStorage['migrationapp.access_token']` (authenticated Playwright session, user `evansri.mondragonp@veevart.com`, group `admin`). Executed 2026-07-24 ~17:27Z.

Constants: `clientId = cdff34f1-9774-41b0-a6a3-124bc03d11cb` · `orgId = 00DWI00000CIwZi2AL` (illinois-trainings).

## 0. Preflight

`GET /implementations/cases` → **200** · target `{caseId:"ic-3-22-pos-batches", version:6, feasibility:"auto", defaultOrder:322}` — matches the merged v6 spec (PR #289).

## 1. Start plan run (fully auto — no operator input)

`POST /implementations/plan-runs` body `{clientId, orgId, caseIds:["ic-3-22-pos-batches"]}`
→ **202** `{planRunId:"ec9c6f1d-a9a8-44a4-a37f-cbe25709a727", status:"PENDING", startedAt:"2026-07-24T17:26:57.077Z"}`

Unlike v4 (which parked AWAITING_INPUT for `batchScope`), v6 never parks — it is fully auto.

## 2. Poll to completion

`GET /implementations/runs/ec9c6f1d-...` (t=+14s) → **200**
```json
{"state":"completed","total":2,"done":2,"failed":0,"blocked":0,"running":0,
 "steps":[
   {"name":"Run & schedule the POS Purchase Payment Propagation batch","type":"auto","state":"done"},
   {"name":"Run & schedule the POS Purchase Canceled Report batch","type":"auto","state":"done"}]}
```
Both AUTOMATED T6 steps reached `done`, `failed:0`. No MANUAL handoff, no AWAITING_INPUT.

## 3. Independent POST-verify (Tooling/Data API on illinois-trainings)

The run happened to land on a PRE-state that exercises BOTH code branches at once:

### Step 2 — POSPurchaseCanceledReportBatch — FRESH ENQUEUE + SELF-SCHEDULE
- **PRE:** AsyncApexJob all-time count = **0**; CronTrigger `Veevart - POSPurchaseCanceledReportBatch` = **absent**.
- **POST:** AsyncApexJob all-time = **1** — `Completed`, BatchApex, CreatedDate `2026-07-24T17:27:17Z` (20s after the run started). CronTrigger `Veevart - POSPurchaseCanceledReportBatch` now **WAITING**, NextFireTime `2026-07-24T21:27:17Z` = +240 min — exactly the `System.scheduleBatch(JOB_NAME, 240, 100)` the code declares.
- → The else-branch ran: enqueued once (ran now) AND established the recurring schedule. Verify-by-AsyncApexJob-query-back satisfied.

### Step 1 — POSPurchasePaymentPropagationBatch — IDEMPOTENT NO-OP
- **PRE:** CronTrigger `Veevart - POSPurchasePaymentPropagationBatch` = **WAITING** (recurring schedule already present; the batch self-runs every ~15 min — 91 Completed jobs in the prior 2 days).
- **POST:** AsyncApexJob rows for the class created in the run window [17:26:00–17:31:00Z] = **0**. The step did NOT enqueue. The pre-existing schedule is untouched (NextFireTime `17:39:10Z`, the normal 15-min cadence).
- → The no-op branch ran (CronTrigger present) — the step completed `done` WITHOUT firing a redundant run. Idempotency proven live.

## 4. Verdict

One run demonstrated both halves of the v6 idempotency contract:
- **Fresh path** (CanceledReport, never run): enqueue + verify + self-schedule → `done`.
- **No-op path** (PaymentPropagation, already scheduled): guard short-circuits, no enqueue → `done` (success, not failed/skipped).

Fully auto: `feasibility=auto`, 2 AUTOMATED T6 steps, 0 operator input, 0 MANUAL. The v4 `batchScope` operator input + Cashier Drawer Control MANUAL are gone; scope now mirrors the package (Payment Propagation `new(15)@2000`, Canceled Report `new()`@default).
