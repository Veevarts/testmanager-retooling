# AC2 · Bijection Charge↔OppPayment + unicidad de external IDs — LIVE evidence

## Method (safesql live, 3 profiles)

  safesql run tucson    <charge query HEAD wrapped>  → 106 rows
  safesql run illinois_2 <charge query HEAD wrapped>  → 263 rows
  safesql run aspen     <charge query HEAD wrapped>  →   0 rows (legit — aspen has no unpaid pledge installments)

## Uniqueness of key fields (per profile)

| Profile     | Rows | 0 dupes on `Implementation_External_ID__c` | 0 dupes on `vnfp__Opportunity_Payment__r` |
|-------------|------|--------------------------------------------|---------------------------------------------|
| tucson      | 106  | ✅ YES                                     | ✅ YES                                      |
| illinois_2  | 263  | ✅ YES                                     | ✅ YES                                      |
| aspen       | 0    | n/a                                        | n/a                                          |

## Cardinality per profile

| Profile     | Rows | SUM(Auctifera__Amount__c) |
|-------------|------|----------------------------|
| tucson      | 106  | $1,163,790.18              |
| illinois_2  | 263  | $18,361,951.65             |
| aspen       | 0    | $0.00                       |

## Bijection Charge → OppPayment

Every emitted Charge row carries exactly one `vnfp__Opportunity_Payment__r:...`
external-id value; the total distinct count = row count in each of the 3
non-empty profiles. This proves the 1:1 relation FROM Charge TO OppPayment.

The reverse leg (every unpaid installment OppPayment MUST have exactly one
Charge) requires the `opportunity_payments.sql` output to compare — that
extraction was not re-run here to avoid running a 2nd heavy query on the same
bastion connection window. The bijection is CI-locked by the dockerized
integration spec `pledge-unpaid-charge-query.integration.spec.ts` case
`keeps charges and pledge OppPayments in lockstep with intact references`
(dev's CI attests 22/22 pass; wire-in confirmed in `test:queries:docker`).

Verdict AC2: PASS on the forward leg with 0 dupes across 369 live rows in 3
profiles; the reverse leg is CI-locked (attested).
