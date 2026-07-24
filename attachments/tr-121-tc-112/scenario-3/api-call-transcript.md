# API call transcript — TR-121 (IM-1095 · IC 6.01 customObjectTranslation · illinois-trainings)

Base: `https://zu76ogw8dg.execute-api.us-east-1.amazonaws.com/dev/api` · Bearer token from `localStorage['migrationapp.access_token']` (authenticated Playwright session, user `evansri.mondragonp@veevart.com`, group `admin`, frontend `migration.dev.rtl.veevartapp.com`). Executed 2026-07-24 ~04:45Z.

Constants: `clientId = cdff34f1-9774-41b0-a6a3-124bc03d11cb` · `orgId = 00DWI00000CIwZi2AL` (illinois-trainings, `ilholocaustmuseum--trainings.sandbox.my.salesforce.com`).

## 0. Preflight — case in dev catalog

`GET /implementations/cases` → **200** · target present:
```json
{"caseId":"ic-6-01-override-field-labels","version":3,"feasibility":"auto","defaultOrder":601,"category":"TICKETING"}
```
**Version note:** dev catalog is at **v3**, not the **v2** delivered by PR #264. A tracked same-day follow-up **PR #267 "IM-1095b: IC 6.01 v3 — drop the Group & Reservation 'Item' override"** (commit `4f07e718`) reduced the case from 10 overrides → 9 (removed the `Auctifera__Museum_Offer_Item__c.Auctifera__Group_Reservation__c → "Item"` override) and dropped all `optional` flags. The op under test (PR #264) is unchanged; the live run necessarily executes the current dev spec (v3, 9 overrides).

## 1. Start plan run

`POST /implementations/plan-runs` body `{clientId, orgId, caseIds:["ic-6-01-override-field-labels"]}`
→ **202** `{planRunId:"0979a5fe-eb2e-4bcd-af81-a50ea99c888c", status:"PENDING", startedAt:"2026-07-24T04:45:38.825Z"}`

## 2. Poll to completion

`GET /implementations/runs/0979a5fe-...` (t=+12s) → **200**
```json
{"state":"completed","total":1,"done":1,"running":0,"blocked":0,"failed":0,"pending":0,
 "cases":[{"caseId":"ic-6-01-override-field-labels","feasibility":"auto","state":"done","tools":["T3"],
   "steps":[{"name":"Override the Auctifera group, reservation, ticket-offer, and POS field labels","type":"auto","state":"done"}]}]}
```

The single AUTOMATED T3 `customObjectTranslation` step reached **`done`** with **failed:0**. Because the op reports `success=false` (→ step not clean-done) if the async metadata deploy fails OR if the `FieldDefinition` verify finds any resolved field's effective label ≠ its override, a clean `done` means the deploy succeeded AND all 9 v3 overrides verified live. This is the live proof of the deploy → poll → FieldDefinition-verify roundtrip for the FIRST deploy-based T3 op (no per-step operations endpoint exists on the API; the verdict is corroborated independently below via Tooling API).

The API exposes no per-field step-operations endpoint (`/steps/:caseRunId/:stepRunId` → 404); the definitive per-field evidence is the independent Tooling API POST-verify.

## 3. Independent POST-verify (Tooling API on illinois-trainings — NOT the run's self-report)

`SELECT QualifiedApiName, Label FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='<obj>' AND QualifiedApiName IN (...)` for the 4 objects.

**PRE** (pre-baseline-labels.txt) and **POST** (post-verify-labels.txt) are **identical** — 0 deltas:
- The **9 v3-targeted fields** were ALL already at their museum target on illinois pre-run → the run re-deployed the same labels and each still verified (**idempotency proof**, all 9): Account=Household/Organization, Museum_Offer=Ticket Offer, Museum_Offering_Price=Ticket Offer Price (after taxes), Museum_Offering_Subtotal=Ticket Offer Price (before taxes), Related_Exposition=Related Exhibition/Event, Related_Exposition_Id=Related Exhibition/Event ID, Exposition=Exhibition/Event, Client=Client (Contact), Client2=Client (Household/Organization).
- **Blast-radius witnesses (untouched):** `Auctifera__Group_Reservation__c.Auctifera__Status__c` = "Status" (never in spec) AND `Auctifera__Museum_Offer_Item__c.Auctifera__Group_Reservation__c` = "Ticket" (in v2, dropped by v3/#267) — both preserved. A field NOT named by the current spec is left exactly as-is.

Definitive live proof:
- **The v3 auto case runs end-to-end via the Migration App API** (state=completed, step=done, failed=0).
- **The deploy/poll/FieldDefinition-verify roundtrip works live** for the first deploy-based T3 op.
- **Idempotency**: 9/9 v3-targeted fields already at target → re-deploy → still verified → clean done (no error, no duplicate state).
- **Non-destructive / blast-radius**: the 2 non-targeted fields (Status; the dropped Group_Reservation→Item) keep their prior labels.
- Because illinois had no drift on any v3-targeted field, there is **no live label FLIP to observe** — the drifted field (`Group_Reservation` on Museum_Offer_Item = "Ticket") is exactly the one v3/#267 intentionally stopped targeting. The label-FLIP behavior is covered by jest (adapter test 1 "DEPLOYS the resolved field-label override and verifies") + the dev's live proof on CamiloDevOrg.
