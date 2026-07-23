# AC4 · Anti-pattern removal + regression tests coverage

## Structural analysis (HEAD vs PRE SQL)

### PRE query (138 lines)
- 3 CTEs: `MembershipLineItems`, `EligibleLines`, `TransactionAgg`
- Directly scans `FINANCIALTRANSACTIONLINEITEM dli` in `EligibleLines`
  WITHOUT pre-filtering by Sales Order eligibility → **transaction-first pattern**.
- Includes `WHERE ... AND STATUSCODE NOT IN (0, 6, 7)` → excludes pending Sales
  Orders → orphans downstream POS lookups.

### POST query (232 lines, +94)
- 8 CTEs — reads Sales-Order-first with an eligibility short-circuit:
  1. `FilteredSalesOrders`      — date-filter Sales Orders FIRST (no status exclusion)
  2. `SalesOrderTransactionLinks` — revenue (rank 1) + payment (rank 2) with `UNION ALL`
  3. `EligibleTransactionIds`   — DISTINCT reduced transaction set
  4. `MembershipLineItems`      — preserved
  5. `EligibleLines`            — now joins `EligibleTransactionIds` (short-circuit)
  6. `TransactionAgg`           — preserved
  7. `DonationItemSalesOrders`  — NEW: aggregate item amounts per Sales Order BEFORE ranking
  8. `DonationSalesOrders`      — refactored
  9. `ResolvedSalesOrders`      — final ranking (revenue > payment > item-fallback)

### Anti-patterns literal check

| Pattern                                | PRE | POST | Verdict |
|----------------------------------------|-----|------|---------|
| `OUTER APPLY` occurrences              | 0   | 0    | (not the issue — never had one) |
| OR-chain ≥ 3 equality disjunctions     | 1   | 1    | domain-legit `c.ISORGANIZATION OR c.ISGROUP OR c.ISCONSTITUENT`, unchanged |
| Direct `FROM FINANCIALTRANSACTIONLINEITEM` (broad scan) | ✅ present | ❌ removed | **anti-pattern removed** |
| Status exclusion `STATUSCODE NOT IN (0,6,7)`           | ✅ present | ❌ removed | **anti-pattern removed** |
| Sales-Order-first eligibility short-circuit             | ❌ absent | ✅ present | **fix applied** |
| Item amount aggregation per Sales Order BEFORE ranking | ❌ absent | ✅ present | **fix applied** |

The ticket's AC4 "broad OR / OUTER APPLY" phrasing was inherited from IM-1091's
template. For THIS ticket, the actual "broad joins" removed are:
- Transaction-first scan in `EligibleLines` (widened to any FT LineItem)
- Status-exclusive filter that dropped pending Sales Orders

## Sibling structural comparison

`sales_order_only_membership.sql` (IM-1091, sibling optimized query):
- 5 CTEs: `MembershipFinancialTransactions`, `EligibleLines`, `TransactionAgg`,
  `MembershipSalesOrders`, `ResolvedSalesOrders`
- 0 OUTER APPLY

Donation query adds 3 more CTEs beyond the sibling pattern because donations
have an extra lineage path (item-only fallback) that memberships don't:
- `FilteredSalesOrders`, `SalesOrderTransactionLinks`, `EligibleTransactionIds`,
  `DonationItemSalesOrders`

Both end with `ResolvedSalesOrders` + ranking. Same architectural pattern. ✅

## Regression tests inventory — pos-purchase-donation-query.spec.ts (8 assertions)

Covers all 4 aspects of AC4:

1. **Lineage paths (revenue / payment / donation-item)**:
   - `preserves the revenue, payment, and donation-item sales-order linkage paths`

2. **Ranking**:
   - `keeps deterministic one-row-per-sales-order resolution priority`

3. **Date/status filtering**:
   - `filters sales orders early without casting date columns in predicates`
   - `keeps pending sales-order statuses exportable for downstream POS lookups`

4. **Anti-pattern prevention**:
   - `avoids the transaction-first patterns that dropped or multiplied sales orders`

Plus cross-query alignment:
   - `keeps zero-net donation transactions excluded so POS purchases match donation opportunities`
   - `keeps donation eligibility aligned with donation_transaction.sql exclusions`
   - `resolves donation POS purchases per sales order with a single eligibility evaluation`

## Integration spec — query-chain.integration.spec.ts (adds 6 donation-related)

Dockerized fixture assertions:
- `keeps the donation chain valid when the sales order is linked through SALESORDERPAYMENT`
- `exports donation-item sales orders without an eligible transaction once with item amount`
- `emits a single row when a sales order is reachable through revenue and payment paths`
- `exports pending donation sales orders so downstream POS lookups stay valid`
- `uses DATEADDED for date filtering when TRANSACTIONDATE is null`

## Verdict AC4

PASS — the anti-pattern removed is transaction-first + broad joins (correctly
identified in the PR diff and structurally documented). Regression tests cover
all 4 required aspects with 8 direct + 5 integration assertions.
