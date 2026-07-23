# Live master template verification — dev (Migration App)

Fetched 2026-07-23 ~20:20 UTC via `GET https://zu76ogw8dg.execute-api.us-east-1.amazonaws.com/dev/api/implementations/plan-templates` inside the authenticated Playwright Cognito session (user `evansri.mondragonp@veevart.com`, group `admin`).

## Master template on dev

```json
{
  "templateId": "master-core-implementation",
  "version": 1,
  "kind": "master",
  "name": "Veevart Core Setup (master)",
  "description": "Veevart master template: every active implementation case (all auto/hybrid automation plus every manual-tier handoff case) except the excluded ic-veevart-auth outlier, ordered by defaultOrder.",
  "caseRefsCount": 76,
  "orderRange": [100, 904],
  "orderingAscending": true,
  "hasVeevartAuth": false,
  "dependsOnStamped": [
    { "caseId": "ic-4-05-transaction-journal-layouts", "dependsOn": ["ic-4-01-specific-funds-debit-credit"] },
    { "caseId": "ic-8-02-resources-setup", "dependsOn": ["ic-3-03-rename-tabs-and-labels"] }
  ]
}
```

## Verification vs the IM-1096 target state

| Invariant | Expected (per PR #266) | Live dev | Match? |
|---|---|---|---|
| Master template exists | Yes, kind='master' | Yes, kind='master' | ✅ |
| caseRefsCount | 76 | 76 | ✅ |
| ic-veevart-auth EXCLUDED | Yes | Yes (absent from caseRefs) | ✅ |
| DEPENDS_ON ic-4-05 → ic-4-01 | Stamped | Stamped | ✅ |
| DEPENDS_ON ic-8-02 → ic-3-03 | Stamped | Stamped | ✅ |
| Ordering by defaultOrder ascending | Yes | Yes | ✅ |
| No dangling dependsOn targets | Yes | Yes (both targets in caseRefs) | ✅ |
| Description reflects predicate policy | Yes | Yes ("every active implementation case ... except ic-veevart-auth") | ✅ |

## Feasibility breakdown drift (informational, NOT a defect)

Local checkout (merge-commit `5c3e1aa`) vs live dev catalog:

| Feasibility | Local (5c3e1aa) | Dev (live) | Delta |
|---|---:|---:|---|
| auto | 24 | 26 | +2 |
| hybrid | 33 | 31 | −2 |
| manual | 19 | 19 | 0 |
| **Total** | **76** | **76** | **0** |

Root cause: 2 cases flipped hybrid → auto in commits merged AFTER IM-1096 (2026-07-16):
- `ic-3-22-pos-batches` v4 → v5 (IM-1079 delivery, IC 3.22)
- `ic-5-2-donation-membership-internal-notification` v2 → v3 (later IC flip)

The predicate contract is UNAFFECTED — count stays 76, ic-veevart-auth stays the only exclusion, the bijection master = catalog \ EXCLUDE_FROM_MASTER holds byte-for-byte with the current dev catalog. This IS the intended behavior of the refactor: as cases flip feasibility over time, the predicate keeps admitting them without pin-list maintenance.

## Conclusion

Scenario 5 passes on live evidence:
1. Master template was seeded at `master-core-implementation` v1 with the predicate-derived 76 caseRefs.
2. Every AC target of TC-109 that maps to "the master must contain X" is satisfied by the live dev state.
3. No POST to `/implementations/plan-templates` was required — dev was already in the target state at the time of QA sign-off.

The prod re-seed is a downstream deployment step (out of scope for this ticket's QA); this scenario closes on the dev verification.
