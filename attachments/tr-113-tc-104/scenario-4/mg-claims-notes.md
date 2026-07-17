# AC4 · Matching-gift claims incluidos — LIVE Tucson evidence

## Static SQL evidence (HEAD)

The HEAD SQL adds an `OR EXISTS (REVENUEMATCHINGGIFT ... ISACTIVE=1)` predicate
to the base `Pledges` CTE. This is the mechanism the PR body describes as the
fix for the missed MG-claim installments.

```sql
WITH Pledges AS (
    SELECT ft.ID AS PledgeID
    FROM FINANCIALTRANSACTION ft
    WHERE ft.[TYPE] = 'Pledge'
        OR EXISTS (
            SELECT 1 FROM REVENUEMATCHINGGIFT rmg
             WHERE rmg.ID = ft.ID AND rmg.ISACTIVE = 1
        )
),
```

vs BASE (PRE, `TYPE='Pledge'` only). The additional predicate opens the gate to
active matching-gift claims that share the pledge installment model in Altru.

## LIVE Tucson evidence

Running the identical query BASE vs HEAD via safesql on the tucson profile:

  PRE  (TYPE='Pledge' only):        88 rows
  POST (Pledge OR active MG-claim): 106 rows
  Delta:                            +18 rows

**PR body claim:** "Tucson: 18 MG-claim installments"
**Live Tucson delta:** exactly 18 (100% match) 🎯

## Field contract of the added rows

The 18 MG-claim installments in the POST output carry the SAME 7-column
field contract as the pledge installments (checked in AC1: 106/106 rows
have Status=Unpaid, Type=NULL, Technical=1, etc.). This is proof that
the fix did NOT introduce a parallel code path with a different contract
for MG claims — they flow through the same emission logic.

## Partial coverage note

The other 4 tenants named in the PR body (MOAD 113 / Long Island 40 /
Everson 10 / High Desert 3) are NOT reachable from this workstation
(safesql profiles missing). The mechanism is verified statically for all
tenants (same SQL, same WITH clause), and Tucson's row count matches
exactly, giving high confidence the same delta shape applies to the
other tenants.

Status: `passed` for Tucson (18/18 empirical); other 4 attested by dev
via cross-tenant safesql (`a3535d46d759`).
