# AC1 · Spec.ts contract simulation — batchScope como required operator input

## Part 1 · JSON spec HEAD vs BASE (static diff)

  BASE-SHA: 5272434f · v3 (pre-fix) · 40 lines
  HEAD-SHA: 8d66dba6 (merge-commit) · v4 (post-fix) · 54 lines
  Delta: +14 lines net

### BASE (v3) — hardcoded constant

```
"description": "... SCOPE is a PM-editable constant."
"apex":       "// PM-editable: batch chunk size passed to Database.executeBatch.
              final Integer BATCH_SCOPE = 200;
              Id jobId = Database.executeBatch(new Auctifera.POSPurchasePaymentPropagationBatch(), BATCH_SCOPE);"
```

**No `requiredInputs` array present in step 1.** The scope is a literal constant
in Apex source.

### HEAD (v4) — required operator input

```
"description": "... SCOPE is a REQUIRED operator input (`batchScope`, recommended default 200
              = Salesforce standard batch chunk) so it is overridable per client
              — PM to CONFIRM the operational default (decision confidence 70)."
"apex":       "// Operator-supplied batch chunk size passed to Database.executeBatch (records
              // per chunk). Declared as the `batchScope` number input on this step; the run
              // parks AWAITING_INPUT until the IE supplies it. Recommended default 200 (the
              // Salesforce standard batch scope). ...
              // Coerce via Decimal.round so a decimal answer (e.g. 200.5) rounds to a whole
              // number instead of throwing System.TypeException at Integer.valueOf.
              final Integer BATCH_SCOPE = Integer.valueOf(Decimal.valueOf('{{batchScope}}').round());
              Id jobId = Database.executeBatch(new Auctifera.POSPurchasePaymentPropagationBatch(), BATCH_SCOPE);"
"requiredInputs": [
    {
        "key": "batchScope",
        "type": "number",
        "label": "POS batch scope (whole number of records per chunk)",
        "description": "...",
        "placeholder": "200",
        "required": true,
        "constraints": { "min": 1, "max": 2000 }
    }
]
```

## AC1 declarative check on HEAD JSON

| Assertion                                              | HEAD | BASE |
|--------------------------------------------------------|------|------|
| Case version = 4                                       | ✅   | v3   |
| Template version = 4 (lockstep with case)              | ✅   | 1    |
| Step 1 kind = AUTOMATED, toolName = T6                 | ✅   | ✅    |
| Step 1 has `requiredInputs` array                       | ✅   | ❌    |
| `batchScope` input declared                            | ✅   | ❌    |
| Input type = number                                    | ✅   | -    |
| Input required = true                                  | ✅   | -    |
| Constraints min = 1                                    | ✅   | -    |
| Constraints max = 2000                                 | ✅   | -    |
| Placeholder = "200"                                    | ✅   | -    |
| Apex uses `{{batchScope}}` template placeholder        | ✅   | ❌    |
| Apex uses `Decimal.round()` safety coercion            | ✅   | ❌    |
| Step 2 kind = MANUAL (Cashier Drawer Control)          | ✅   | ✅    |

Verdict: HEAD 13/13 assertions PASS · BASE fails 8 assertions (all the operator-input
work is the delta).

## Part 2 · jest ic-3-22-pos-batches.spec.ts on the clone

```
$ npx jest --runInBand src/implementations/infrastructure/seeds/specs/ic-3-22-pos-batches.spec.ts

PASS src/implementations/infrastructure/seeds/specs/ic-3-22-pos-batches.spec.ts
  ic-3-22-pos-batches.json
    ✓ parses against the publish-plan-template CLI schema (v4, hybrid) (4 ms)
    ✓ keeps case.version and template.version in lockstep (append-only single-case template must publish the current case version)
    ✓ has 2 ordered steps: AUTOMATED T6 enqueue -> MANUAL drawer-control handoff (7 ms)
    ✓ launches the batch via the real global Auctifera class, verified by AsyncApexJob query-back
    ✓ exposes the batch chunk size as a REQUIRED number operator input (batchScope, 1-2000)

Test Suites: 1 passed, 1 total
Tests:       5 passed, 5 total
Time:        3.031 s
```

Note: dev PR body said "4 tests" — actual count is **5**. Minor discrepancy in
the ticket update (the ticket text was written before a final test was appended).

## Verdict AC1

PASS — HEAD JSON spec declares `batchScope` as required number input with correct
constraints (1-2000, default 200), Apex uses `{{batchScope}}` template with
`Decimal.round` safety, spec.ts CI-locks all 5 assertions on the merge-commit.
