# AC1 · Cardinalidad — 1 fila por eligible donation-only Sales Order

## Live safesql runs (2026-07-22T12:50-12:56Z)

Profiles reached (bastion up, all 3 completed successfully):

| Profile     | Rows   | distinct `Implementation_External_ID__c` | Dupes | Runtime |
|-------------|--------|-------------------------------------------|-------|---------|
| tucson      | 20,442 | 20,442                                    | **0** | ~64 s   |
| illinois_2  | 18,282 | 18,282                                    | **0** | ~63 s   |
| aspen       | 305    | 305                                       | **0** | ~13 s   |
| **TOTAL**   | **39,029** | **39,029**                            | **0** | —       |

## Column contract (13 columns) — matches sibling `sales_order_only_membership.sql`

Fields emitted (sample from Tucson):
```
Implementation_External_ID__c   (PK, GUID)
LookUp_ID_Legacy                (e.g. "8-11332715")
Revenue_ID_legacy__c            ("rev-{revenue_id}" or NULL for item-only fallback)
Auctifera__Source__c            (e.g. "Daily Sales", "Online Sales")
Auctifera__Status__c            (Sold | Refunded | Pending)
Auctifera__Subtotal_before_discount__c
Auctifera__Subtotal__c
Auctifera__Total__c
Auctifera__Client__c
Auctifera__Client2__c
+ 3 more
```

## PRE query — timeout on Tucson (reproduces the bug 🎯)

```
node ~/tools/safesql/safesql.mjs run tucson pre-wrapped.sql --allow-writes
[safesql] profile=tucson query_sha=4070068bae6e started=2026-07-22T12:51:46.788Z
[safesql] error: Timeout: Request failed to complete in 120000ms
```

**Second attempt (same profile, 5 min later)**:
```
[safesql] profile=tucson query_sha=4070068bae6e started=2026-07-22T12:56:06.588Z
[safesql] error: Timeout: Request failed to complete in 120000ms
```

Verdict: the PRE query **does NOT complete reliably on the Tucson backup within 120 s**
— this is the exact "stall on large backups" bug the ticket reports. The POST query
completes successfully in ~64 s on the same profile → **objective met**.

## Verdict AC1

PASS on 3 reachable profiles: 39,029 rows total, 0 dupes on `Implementation_External_ID__c`
(row grain = 1 per Sales Order, per the ranking priority in the ResolvedSalesOrders CTE).
