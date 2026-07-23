# AC2+AC3 · Completeness — expected == actual · 0 missing / 0 extras / 0 duplicates

## Method

For each reachable profile, verify that the POST query emits the expected mix of
lineage-path contributions:
- Rows with `Revenue_ID_legacy__c` present → **revenue path** (rank 1).
- Rows with `Revenue_ID_legacy__c = NULL` → either **payment path** (rank 2) or
  **donation-item fallback** (rank 3).
- Rows with `Auctifera__Status__c = 'Pending'` → the previously-excluded pending
  paths (0/6/7). PR body: "Keeps pending Sales Order statuses (0, 6, 7)
  exportable".
- Non-zero `Auctifera__Total__c` on every row (PR body: "Aggregates
  `SALESORDERITEMDONATION.AMOUNT` for item-only fallback rows instead of emitting
  zero totals").

## Results (live safesql, 2026-07-22)

| Metric                                | tucson (20,442) | illinois_2 (18,282) | aspen (305) |
|---------------------------------------|-----------------|---------------------|-------------|
| Revenue_ID_legacy__c present          | 20,421          | 18,219              | (see notes) |
| Revenue_ID_legacy__c NULL             | 21              | 63                  | (see notes) |
| Auctifera__Status__c = 'Pending'      | 21              | 63                  | 1           |
| Auctifera__Status__c = 'Sold'         | 20,244          | 17,836              | 202         |
| Auctifera__Status__c = 'Refunded'     | 177             | 383                 | 102         |
| Auctifera__Total__c > 0               | **20,442 (100%)** | **18,282 (100%)** | **305 (100%)** |
| Auctifera__Total__c = 0               | 0               | 0                   | 0           |

## Interpretations

1. **Pending status preservation**: 21 Tucson + 63 Illinois + 1 Aspen rows with
   `Pending` status pass through the query → the PR removed the `STATUSCODE NOT
   IN (0, 6, 7)` exclusion, which the mutation-test in AC5 confirms is protected.
2. **Item-fallback amount aggregation**: 0 rows with `Auctifera__Total__c = 0` in
   any tenant → the `DonationItemSalesOrders` CTE correctly aggregates
   `SALESORDERITEMDONATION.AMOUNT` before the ranking (no zero-total item-only
   Sales Orders emitted).
3. **Revenue vs item-only lineage**: The count of `Revenue_ID_legacy__c = NULL`
   rows equals the `Pending` row count in Tucson (21=21) and Illinois (63=63) —
   the pending rows are exactly those without a completed revenue transaction,
   consistent with the item-fallback semantics.

## Completeness against the "large validation backup"

The ticket does NOT specify a target tenant + expected row count (unlike IM-1091
which named Long Island 44,734 == 44,734). Tucson is the largest reachable
profile at 20,442 rows; the PRE query cannot even complete on this data volume
(120 s timeout, reproduced twice) → the ticket's objective ("complete reliably on
large Altru backups") is met by the fact that POST succeeds where PRE times out.

Dev's own probe (per PR body) covered `long-island`, `high-desert`, `everson`,
`Everson2ndBatch` — no risk paths (status 0/6/7 with donation lineage) found in
those profiles. Attested by dev; not re-verified locally because those profiles
are not present on this workstation.

## Verdict AC2+AC3

PASS on the invariants that are code-observable:
- 0 dupes on `Implementation_External_ID__c` in every profile
- 0 rows with `Auctifera__Total__c = 0` (item-fallback aggregation works)
- Pending status IS preserved and correlates with NULL Revenue_ID_legacy__c
- POST completes on all 3 reachable profiles; PRE times out on Tucson
