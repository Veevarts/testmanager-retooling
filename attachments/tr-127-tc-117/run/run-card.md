# IE Run Card — IC 6.03 History Tracking for Ticketing (TR-127 / TC-117)

- **caseId**: `ic-6-03-history-tracking-ticketing` **v3** (feasibility `hybrid`)
- **PR under test**: Veevarts/MigrationAppBackend#244 (MERGED 2026-07-15, merge commit `140e00d4`) — spec-only
- **workspace/client**: Test IM cases Org Tucson — `clientId=cdff34f1-9774-41b0-a6a3-124bc03d11cb`
- **org**: illinois-trainings — `orgId=00DWI00000CIwZi2AL`
- **path**: A (API-driven, plan-runs) — token from logged-in Cognito session (group `admin`)
- **startedBy**: evansri.mondragonp@veevart.com

## Preflight
- GET /implementations/cases → 200 · `ic-6-03` present at **v3**, feasibility `hybrid` (catalog matches PR, no drift)
- PRE baseline (illinois): Inventory_Service 7/7 exact · Museum_Offer_Item **18** (17 keep + 1 EXTRA
  Ticket_Item_Subtotal_Canceled) · Museum_Offer 15 custom + Name · Group_Reservation 7/7 (correct
  non-formula twins). → the run's ONLY destructive effect is untracking the 1 extra on Museum_Offer_Item.

## Run 1 (primary)
- planRunId: `a92bc85f-ed88-41f9-8da9-280751fabba4`
- caseRunId: `2357f1e7-f749-4b91-9e25-ab9c34d7c131`
- state: **completed** · total=5 done=5 failed=0
- 4 AUTOMATED (exclusive historyTracking) `done`; step 5 MANUAL parked `blocked-human` then **attested**
  (POST /handoff → 202, attesting-without-executing, test workspace)

## Run 2 (idempotency, S6)
- planRunId: `502cad97-dd24-441d-80cb-a02a2804ed76`
- caseRunId: `3fc15769-3ce8-4037-9a8c-7a28f8882ef6`
- state: **completed** · total=5 done=5 failed=0 (MANUAL re-attested → 202)
- delta run1→run2 = NONE on all 4 objects (pure idempotent no-op)

## Steps (both runs, order)
1. Enable field-history tracking on Exhibition/Event (Inventory_Service, 7, exclusive) — done
2. Enable field-history tracking on Ticket Item (Museum_Offer_Item, 17, exclusive) — done (untracked 1 extra)
3. Enable field-history tracking on Ticket Offer (Museum_Offer, 15, exclusive) — done (Name preserved)
4. Enable field-history tracking on Ticketing / Reservation (Group_Reservation, 7, exclusive) — done
5. Tick 'Ticket offer name' on Ticket Offer (MANUAL / handoff) — blocked-human → attested (202)

## Attestation note (S5)
The standard Name field ('Ticket offer name' / 'Museum Offer Name') cannot be set via metadata replay
(no CustomField record). The MANUAL step parks as blocked-human; the harness NEVER auto-executes it.
Attested via POST /handoff by explicit QA instruction (attesting-without-executing, test workspace).
Note: on illinois the Name field was ALREADY tracked PRE, so there is no real pending UI work — and
exclusive mode (which enumerates only CustomFields) left Name tracked (POST Name tracked=True), proving
it never untracks the standard Name. In a customer org the IE would tick Name by hand before attesting.
