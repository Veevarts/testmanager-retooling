#!/usr/bin/env bash
# POST-verify query bundle for IC 9.1 Merchant Batches — second QA cycle.
# Run this AFTER the IE executes the plan in MigrationApp against illinois-trainings
# for both Square (AC2 idempotency re-run) and Stripe (AC3 verified no-op with
# leftover Square jobs present) merchant selections.
# Requires: authenticated `sf` CLI + target-org alias `illinois-trainings`.

set -euo pipefail
ORG="illinois-trainings"
OUT="$(cd "$(dirname "$0")" && pwd)"

echo "== AC1+AC5 · Auctifera__Batch_Settings__c org-default flags =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, SetupOwnerId, Auctifera__Schedule_Square__c, Auctifera__Schedule_Stripe__c FROM Auctifera__Batch_Settings__c" \
  > "$OUT/scenario-1/POST-batch-settings.json"
echo "  Expected: Schedule_Square = true (preserved from prior + Square re-run)"

echo "== AC1+AC5+AC6 · CronTrigger for Square + meta-scheduler + info sync =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, CronJobDetail.Name, State, NextFireTime, TimesTriggered FROM CronTrigger WHERE CronJobDetail.Name IN ('Veevart - Automatic Batch Schedule', 'Veevart - Square charge fix', 'Veevart - Square refund status update', 'Veevart - Square payment synchronization') ORDER BY CronJobDetail.Name" \
  > "$OUT/scenario-1/POST-square-crons.json"
echo "  Expected AC1: charge fix + refund status update crons PRESENT (required)"
echo "  Expected AC5: meta-scheduler 'Veevart - Automatic Batch Schedule' PRESENT (required)"
echo "  Expected AC6: 'Veevart - Square payment synchronization' PRESENT (informational, may be absent depending on package version)"

echo "== AC2 · Idempotency — cron count after Square re-run should match PRE =="
sf data query --target-org "$ORG" --json --query \
  "SELECT COUNT(Id) totalSquareCrons FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Veevart - Square%' OR CronJobDetail.Name = 'Veevart - Automatic Batch Schedule'" \
  > "$OUT/scenario-2/POST-cron-count-after-rerun.json"
echo "  Expected: 4 (PRE) == 4 (POST after re-run) — no duplicate jobs"

echo "== AC3 · Stripe verified no-op — recent Square AsyncApexJobs count =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, ApexClass.Name, ApexClass.NamespacePrefix, Status, CreatedDate FROM AsyncApexJob WHERE ApexClass.NamespacePrefix = 'Auctifera' AND ApexClass.Name IN ('SquareChargeFixBatch', 'SquareRefundBatch') AND CreatedDate = LAST_N_DAYS:1 ORDER BY CreatedDate DESC LIMIT 30" \
  > "$OUT/scenario-3/POST-async-jobs-last-1-day.json"
echo "  Expected AC3: Stripe branch completed as SUCCESS with skipped-as-success note."
echo "  KEY validation: dev's #271 fix uses snapshot/diff, so any leftover Square jobs from"
echo "  Square runs BEFORE the Stripe run must NOT false-fail the Stripe verify."
echo "  Check IE's MigrationApp run log: Stripe step status = SUCCESS (not FAILED)."

echo "== AC1 informational · Recent immediate Square run (from Square re-run) =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, ApexClass.Name, Status, CreatedDate FROM AsyncApexJob WHERE ApexClass.NamespacePrefix = 'Auctifera' AND ApexClass.Name IN ('SquareChargeFixBatch', 'SquareRefundBatch') AND CreatedDate = LAST_N_DAYS:1 AND Status IN ('Holding','Queued','Preparing','Processing','Completed') ORDER BY CreatedDate DESC LIMIT 4" \
  > "$OUT/scenario-1/POST-recent-square-jobs.json"
echo "  Expected: 2+ recent jobs (charge fix + refund) in accepted state from the Square re-run."

echo "== AC4 · Unrecognized merchant negative test =="
echo "  This scenario needs IE to force an invalid merchant input via MigrationApp UI"
echo "  (may require bypass of the select validation — record the observed error message)."
echo "  Verify observed error contains 'unrecognized merchantType' (per spec.ts IT5)."

echo "== Done. Compare with PRE-baseline in scenario-1/PRE-*.json =="
