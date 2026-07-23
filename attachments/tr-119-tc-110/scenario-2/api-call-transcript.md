# API call transcript — TR-119 (IM-1074 · IC 8.05 v3 · illinois-trainings)

Base: `https://zu76ogw8dg.execute-api.us-east-1.amazonaws.com/dev/api` · Bearer token from `localStorage['migrationapp.access_token']` of the authenticated Playwright browser session (user `evansri.mondragonp@veevart.com`, group `admin`). Executed 2026-07-23 ~22:03-22:05Z.

Constants: `clientId = cdff34f1-9774-41b0-a6a3-124bc03d11cb` (Test IM cases Org Tucson workspace) · `orgId = 00DWI00000CIwZi2AL` (illinois-trainings).

## 0. Preflight — case in dev catalog

`GET /implementations/cases` → **200** · target present:
```json
{"caseId":"ic-8-05-history-tracking-rentals","version":3,"feasibility":"hybrid","defaultOrder":805}
```

## 1. Start plan run

`POST /implementations/plan-runs`
Body: `{clientId, orgId, caseIds:["ic-8-05-history-tracking-rentals"]}`
→ **202**
```json
{"planRunId":"147f1231-3533-4bbd-ad8d-9e86467ebe20","status":"PENDING","startedAt":"2026-07-23T22:03:37.587Z"}
```

## 2. Poll cycles (5-20s tick)

- t=+8s: run `running`, step 1 `done`, step 2 `running`, steps 3-6 `pending`
- t=+28s: run `paused`, all 5 auto steps `done`, step 6 (MANUAL) `blocked-human`
- counts: total 6 · done 5 · blocked 1 · running 0 · failed 0

## 3. Attest MANUAL step 6 (attesting-without-executing, test workspace only)

`POST /implementations/plan-runs/147f1231-.../steps/5946d1fb-.../36fe3575-.../handoff`
- caseRunId: `5946d1fb-34bb-4a54-9f55-9996f4ff0386`
- stepRunId: `36fe3575-c733-4a54-a331-eac9427ae5ee`
- Body: `{}`
→ **202** `{status:"PENDING", stepRunId:"36fe3575-..."}`

**Attestation guardrail explicit**: the operator UI work (ticking the Name checkbox on 4 rental objects) was NOT performed in illinois-trainings. Only the API `/handoff` endpoint was called to close the step and let the run reach COMPLETED. Verifiable via Setup UI or via the fact that the standard `Name` field on Rental Event / Rental Payment / Display Location / Resource stays with its default (Salesforce won't expose IsFieldHistoryTracked for standard Name via Tooling API in a way that lets us assert this cleanly, but the AC5 scenario documents the intent).

## 4. Final state

- run `completed`, case `done`, all 6 steps `done`
- counts: total 6 · **done 6** · running 0 · blocked 0 · failed 0

## 5. Independent POST-verify (Tooling API on illinois-trainings)

For each of the 5 sobjects, query `SELECT QualifiedApiName, IsFieldHistoryTracked FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='<obj>' AND QualifiedApiName IN (<42 apiNames>)`.

**Result**: 42/42 fields `IsFieldHistoryTracked=true`. See `pre-baseline-tooling.json` (PRE) and `post-verify-tooling.json` (POST) for the raw per-field state.

**Delta**: exactly ONE flip pre→post:
- `Auctifera__Rental_Payments__c.Auctifera__Pos_Purchase__c`: `false → true`

The other 41 fields were already tracked pre-run (illinois-trainings had a prior seed/manual state) and were preserved by the additive behavior of the case (the spec omits `exclusive: true` intentionally).

This is the definitive live proof that the case:
- **Adds tracking to a field that wasn't tracked yet** (Pos_Purchase — the run's only observable state change on this org).
- **Preserves pre-existing tracking on all other 41 fields** (additive, non-destructive).
- **The runtime `{anyOf, label}` matcher resolves correctly** (all 5 label-traps landed on the non-formula variant — see scenario-4 evidence).
