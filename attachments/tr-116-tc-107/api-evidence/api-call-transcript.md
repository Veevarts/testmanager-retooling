# API call transcript — run f2f9e3b0 (IM-1078 · IC 5.23 v3 · illinois-trainings)

Base: `https://zu76ogw8dg.execute-api.us-east-1.amazonaws.com/dev/api` · Bearer token
from `localStorage['migrationapp.access_token']` of the logged-in Migration App session
(all calls made via fetch INSIDE the authenticated browser context — the token never
left the browser). Executed 2026-07-23 ~17:43–18:05 UTC.

## 0 · Preflight — seed check
`GET /implementations/cases` → 200 · 77 cases · target present:
`{"caseId":"ic-5-23-campaigns-page-layout","version":3,"name":"Update Campaigns Page Layout","category":"FUNDRAISING","defaultOrder":523,"active":true,"feasibility":"hybrid"}`

## 1 · Start run
`POST /implementations/plan-runs`
Body: `{"clientId":"cdff34f1-9774-41b0-a6a3-124bc03d11cb","orgId":"00DWI00000CIwZi2AL","caseIds":["ic-5-23-campaigns-page-layout"]}`
→ **202** `{"planRunId":"f2f9e3b0-9ffb-4bbe-915c-af387916e49a","status":"AWAITING_INPUT","startedAt":"2026-07-23T17:43:53.030Z"}`

## 2 · Parked operator input (live discovery — AC1)
`GET /implementations/runs/f2f9e3b0…` → state `awaiting-input`, step "Select and assign
the Veevart Campaign page layout as active" parked with:
`{"type":"select","key":"campaignLayout","label":"Campaign page layout to make active (latest 'Veevart Campaign Layout Vx')","options":["Campaign-Campaign Layout","Campaign-vnfp__Veevart Campaign Layout","Campaign-vnfp__Veevart Campaign Layout V2 - Aug 2022","Campaign-vnfp__Campaign Layout","Campaign-npsp__NPSP Campaign Layout","Campaign-vnfp__Veevart Campaign Layout V3 - Mar 2024"]}`
(6 options discovered live, namespaces reconstructed; the earlier orgfarm run ea0d01e8
returned the same 6 in a DIFFERENT order → per-org live discovery confirmed, no hardcode.)

## 3 · Submit operator input
`POST /implementations/plan-runs/f2f9e3b0…/inputs`
Body: `{"operatorInputs":{"campaignLayout":"Campaign-vnfp__Veevart Campaign Layout V3 - Mar 2024"}}`
→ **202** `{"status":"PENDING","remainingInputs":[]}`

## 4 · Poll until the auto step lands
`GET /implementations/runs/f2f9e3b0…` cycles: `running` (~12 min for the T2 profile
sweep) → step 1 `done`, run `paused`, step 2 `blocked-human` (type handoff), step 3
`pending`. Mid-sweep Tooling probe on the org showed ProfileLayout rows actively
moving to the selected layout — see post-verify/.

## 5 · Attest manual handoffs (explicit QA instruction — work NOT performed, test workspace)
`POST /implementations/plan-runs/f2f9e3b0…/steps/82f5043b…/043ab667…/handoff` → **202**
→ step 2 `done`; step 3 parked `blocked-human` only AFTER step 2's attestation
(sequential parking).
`POST /implementations/plan-runs/f2f9e3b0…/steps/82f5043b…/5a401324…/handoff` → **202**

## 6 · Final state
`GET /implementations/runs/f2f9e3b0…` → **`state: completed` · total 3 · done 3 ·
0 failed** (full JSON in run-f2f9e3b0-final-state.json).

## Observations
- orgfarm comparison run `ea0d01e8` (00Dfj00000QJMx7EAH): same case, auto step took
  ~30–45 min (vs ~12 min on Illinois) but DID complete — slow, not stuck.
- The run detail exposes no timing/error detail per step — polling + org-side Tooling
  probes are the observability tools.
