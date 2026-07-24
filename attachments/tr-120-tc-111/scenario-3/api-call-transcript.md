# API call transcript — TR-120 (IM-1073 · IC 7.02 v2 · illinois-trainings)

Base: `https://zu76ogw8dg.execute-api.us-east-1.amazonaws.com/dev/api` · Bearer token from `localStorage['migrationapp.access_token']` (Playwright session, user `evansri.mondragonp@veevart.com`, group `admin`). Executed 2026-07-24 ~00:52-00:54Z.

Constants: `clientId = cdff34f1-9774-41b0-a6a3-124bc03d11cb` · `orgId = 00DWI00000CIwZi2AL` (illinois-trainings).

## Session note

The Playwright token in localStorage had expired (exp -109 min). Navigating to authenticated routes did NOT auto-refresh it. A single click on the "Continue with Google" login button (Google SSO cookies still alive) refreshed the session to a fresh 60-min token WITHOUT requiring a re-SSO challenge — the localStorage token reissued on redirect to `/csm/my-day`.

## 0. Preflight

`GET /implementations/cases` → **200** · target present: `{caseId:"ic-7-02-history-tracking-gift-shop", version:2}`.

## 1. Start plan run

`POST /implementations/plan-runs` body `{clientId, orgId, caseIds:["ic-7-02-history-tracking-gift-shop"]}`
→ **202** `{planRunId:"d004b4b9-e558-48cc-ac6d-2ff087cd6ff0", status:"PENDING", startedAt:"2026-07-24T00:52:30.620Z"}`

## 2. Poll cycles

- t=+18s: run running, step 1 (validationRule) **done**, step 2 (Client Purchases) **done**, step 3 (Shop Item) pending, step 4 (MANUAL) pending
- t=+30s: run paused, all 3 auto steps **done**, step 4 blocked-human
- counts: total 4 · done 3 · blocked 1 · failed 0

**Step 1 = the NEW validationRule op running live**: deactivate `Restrict_Misc_Gift_Card` on `Auctifera__CatalogItem__c`. Since the rule is ABSENT on illinois-trainings (7 VRs exist, none named Restrict), the op took the **idempotent success no-op branch** — the step completed `done` (did NOT fail under fail-fast). This is the live proof of the "deactivate + absent = success no-op" behavior.

## 3. Attest MANUAL step 4 (2 Name fields, attesting-without-executing)

`POST /implementations/plan-runs/d004b4b9-.../steps/30729595-.../eedc948a-.../handoff`
- caseRunId: `30729595-4926-41ba-9c8c-b234a0e6b154`
- stepRunId: `eedc948a-6e35-45d8-b047-38c8f50d346b`
- Body: `{}` → **202**

**Guardrail explicit**: the UI work (ticking Client Purchase Name + Shop Item Name checkboxes) was NOT performed in illinois-trainings. Only the API `/handoff` closed the step. Test-workspace pattern per TR-115/116/117/119.

## 4. Final state

run `completed`, case `done`, all 4 steps `done`. counts total 4 · **done 4** · failed 0.

## 5. Independent POST-verify (Tooling API)

`SELECT QualifiedApiName, IsFieldHistoryTracked FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName='<obj>' AND QualifiedApiName IN (<23 apiNames>)` for both objects.

**PRE-baseline** (pre-baseline-tooling.json): **20/23** tracked (3 untracked on Client Purchases: Contact, POS_Purchase, Payment_Method).
**POST** (post-verify-tooling.json): **23/23** tracked.

**Delta = exactly 3 flips**:
- `Auctifera__ClientPurchase__c.Auctifera__Contact__c`: false → true
- `Auctifera__ClientPurchase__c.Auctifera__POS_Purchase__c`: false → true
- `Auctifera__ClientPurchase__c.Auctifera__Payment_Method__c`: false → true

The other 20 fields were already tracked and were **preserved** (additive behavior — the spec omits `exclusive: true`).

Definitive live proof:
- **historyTracking adds the untracked fields** (3 flips on Client Purchases).
- **Preserves the 20 pre-tracked** (additive).
- **The runtime matcher resolves the double label-trap** (`Total2__c` tracked, not the deprecated `Total__c`/`Total_Amount__c`; `Paid_Value__c` tracked, not `Paid_Value1__c`) — see scenario-1 evidence.
- **The NEW validationRule op runs live** (step 1 done via the no-op branch).
