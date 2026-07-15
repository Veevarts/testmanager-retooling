#!/usr/bin/env bash
# POST-verify query bundle for IC 9.2 case v3 execution in illinois-trainings.
# Run this AFTER the IE executes the plan in MigrationApp against illinois-trainings.
# Output artifacts drop into ./POST-* files ready for QA re-comparison against PRE.
# Requires: authenticated `sf` CLI + target-org alias `illinois-trainings`.

set -euo pipefail
ORG="illinois-trainings"
OUT="$(cd "$(dirname "$0")" && pwd)"

echo "== AC1 · Auctifera Batch Settings (should have 3 flags true post-run) =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, SetupOwnerId, Auctifera__Schedule_People__c, Auctifera__Schedule_Accounting__c, Auctifera__Schedule_Notification_Manager__c, Auctifera__Schedule_Membership__c, vnfp__Schedule_Donation__c, vnfp__Schedule_Specific_Fund__c, vnfp__Schedule_Recurring_Donation__c, vnfp__Schedule_NFP_Accounting__c FROM Auctifera__Batch_Settings__c" \
  > "$OUT/scenario-1/POST-batch-settings.json"
echo "  saved -> scenario-1/POST-batch-settings.json"
echo "  Expected AC1: People=true, Accounting=true, Notification_Manager=true (org-default row)"

echo "== AC2 · vnfp Fundraising Settings (Donation RT id must be in CSV) =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, SetupOwnerId, vnfp__Automatic_Fund_Assignment_Record_Types__c FROM vnfp__Fundraising_Settings1__c" \
  > "$OUT/scenario-2/POST-fundraising-settings.json"
echo "  saved -> scenario-2/POST-fundraising-settings.json"
echo "  Expected AC2: Donation RT '012an000004vZ6vAAE' present in CSV (already true pre-run; idempotent no-op expected)"

echo "== AC3 · vnfp meta-scheduler + ChargeItemInvoiceBatch cron (required) + info crons =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, SetupOwnerId, Auctifera__Schedule_Membership__c, vnfp__Schedule_Donation__c, vnfp__Schedule_Specific_Fund__c, vnfp__Schedule_Recurring_Donation__c, vnfp__Schedule_NFP_Accounting__c FROM Auctifera__Batch_Settings__c" \
  > "$OUT/scenario-3/POST-batch-settings-vnfp.json"
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, CronJobDetail.Name, State, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name IN ('Veevart - Automatic Batch Schedule','Veevart NFP - Automatic Batch Schedule','Veevart NFP - ChargeItemInvoiceBatch','Veevart NFP - Roundup Donation Fund Assignment','Veevart NFP - Recurring donation','Veevart NFP - Opportunity General Fund Assignment','Veevart NFP - Specific Fund Hierarchy','Veevart - AccountingDiscrepancyNotificationBatch','Veevart - Charge Drawer Control Batch','Veevart - POS Purchase Drawer Control Batch','Veevart - Refund Drawer Control Batch','Veevart - Refunded Item Drawer Control Batch','Veevart - Shop_Returns FundAssignmentBatch') ORDER BY CronJobDetail.Name" \
  > "$OUT/scenario-3/POST-cron-triggers.json"
echo "  saved -> scenario-3/POST-batch-settings-vnfp.json + POST-cron-triggers.json"
echo "  Expected AC3: 5 flags true + daily 'Veevart NFP - Automatic Batch Schedule' + 'Veevart NFP - ChargeItemInvoiceBatch' present"

echo "== AC4 · Fix Contact Roles cron (manual — must appear only after IE hand-schedules from Nonprofit Settings UI) =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, CronJobDetail.Name, State, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name LIKE '%Fix Contact Roles%' ORDER BY CronJobDetail.Name" \
  > "$OUT/scenario-4/POST-fix-contact-roles-cron.json"
echo "  saved -> scenario-4/POST-fix-contact-roles-cron.json"
echo "  Expected AC4: 1 row 'Veevart NFP - Fix Contact Roles' AFTER manual step; empty BEFORE."

echo "== AC5 · Idempotency — capture cron count now, IE re-runs plan, run again =="
sf data query --target-org "$ORG" --json --query \
  "SELECT COUNT(Id) totalVeevartCrons FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Veevart%'" \
  > "$OUT/scenario-5/POST-cron-count-round1.json"
echo "  saved -> scenario-5/POST-cron-count-round1.json"
echo "  Expected AC5: after 2nd IE run, POST-cron-count-round2 must equal round1 (no duplicates)."

echo "== AC1 informational · AsyncApexJob for AccountingDiscrepancyNotificationBatch =="
sf data query --target-org "$ORG" --json --query \
  "SELECT Id, Status, CreatedDate FROM AsyncApexJob WHERE ApexClass.Name = 'AccountingDiscrepancyNotificationBatch' AND ApexClass.NamespacePrefix = 'Auctifera' AND CreatedDate = LAST_N_DAYS:1 ORDER BY CreatedDate DESC LIMIT 5" \
  > "$OUT/scenario-1/POST-async-jobs.json"
echo "  saved -> scenario-1/POST-async-jobs.json"
echo "  Expected AC1 informational: >=1 row after run-now (Holding/Queued/Preparing/Processing/Completed)."

echo "== Done. Re-run QA compare-matrix afterwards. =="
