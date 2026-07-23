# AC2 · Operator override batchScope=500 — DEFERRED to IE run

## PRE-baseline captured

`sf data query --target-org illinois-trainings --json --query "SELECT Id, ApexClass.Name, ApexClass.NamespacePrefix, Status, CreatedDate FROM AsyncApexJob WHERE ApexClass.Name = 'POSPurchasePaymentPropagationBatch' AND ApexClass.NamespacePrefix = 'Auctifera' AND CreatedDate = LAST_N_DAYS:7 ORDER BY CreatedDate DESC"`

**PRE-baseline count**: 0 rows (clean baseline — no `Auctifera.POSPurchasePaymentPropagationBatch`
jobs on illinois-trainings in the last 7 days).

Baseline JSON: `illinois-PRE-baseline.json`

## Pending from you (Evans / IE handoff)

To close AC2 with source-side evidence:

1. Open the MigrationApp UI on illinois-trainings.
2. Trigger the plan `ic-3-22-pos-batches` (v4).
3. When the run parks in AWAITING_INPUT for step 1, **enter `batchScope = 500`**.
4. Wait for the step to complete (should hit the query-back check).
5. Notify QA — I re-run the same `sf data query` and confirm:
   - A new `AsyncApexJob` row exists for class `POSPurchasePaymentPropagationBatch`.
   - Status in accepted state (Holding/Queued/Preparing/Processing/Completed).
   - CreatedDate is within the last minute (attributable to the IE run).
6. If the org has an `Auctifera__Log__c` or equivalent that captures the effective
   batch scope, verify it = 500 for that job.

Status: `not-run` — deferred to IE run.
