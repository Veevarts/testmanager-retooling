# IE Run Card — IC 5.06 Opportunity History & Mandatory (TR-129 / TC-119)

- **caseId**: `ic-5-06-opportunity-history-mandatory` **v3** (feasibility `hybrid`)
- **PR under test**: Veevarts/MigrationAppBackend#243 (MERGED 2026-07-15, merge `5aa676aa`, base `81ada09`) — CODE PR (new T2 setFieldBehavior op)
- **org**: illinois-trainings — `orgId=00DWI00000CIwZi2AL`
- **path**: A (API-driven) — Cognito admin session

## Primary evidence = jest code-contract (org-independent)
- clone @ merge `5aa676aa`, node_modules reused
- t2-page-layout.adapter.spec.ts: **59 passed, 0 failed**
- setFieldBehavior op `-t`: **5 passed** — makes-Required+read-back, never-adds-missing (applied=false+reason), idempotent, verified=false detection, MALFORMED_REQUEST reject
- tsc --noEmit clean
- eslint: 4 errors on t2-page-layout.adapter.ts:578-587 are PRE-EXISTING (git blame c7662086, Camilo 2026-06-16, recordTypes op) — NOT introduced by PR #243; setFieldBehavior's own lines clean; repo has 168 pre-existing lint problems
- genuinely-new: setFieldBehavior base=0, merge=9

## Live end-to-end (illinois)
- Run 1: `0a3fb75f-ad5c-4e5a-b450-a3bf0ee5801e` — completed 3/3, 0 failed
  - Part A (exclusive history): 6 keep-list fields tracked (StageName, Amount, CloseDate, vnfp__Membership_Program__c, npe01__Membership_Start_Date__c, npe01__Membership_End_Date__c); RecordTypeId untouched; matchers resolved vnfp + npe01
  - Record Type MANUAL: parked blocked-human → attested (POST /handoff → 202)
  - Part B setFieldBehavior: parked needs-input → resolved membershipLayout=`Opportunity-npsp__Membership Layout` → both npe01 dates flipped **Edit → Required** (Metadata API layout read-back)
- Run 2 (idempotency): `5682c9b0-984d-493d-8958-02bd15deb51c` — completed 3/3; layout still Required (no dup); Part A stable

## Layout selection note
Discovered options (13) show namespaced fullNames reconstructed by the discovery adapter (npsp__/vnfp__).
- `Opportunity-vnfp__Veevart Membership Layout - V3 - May 2023` (AC's example, active) already had the dates
  Required → idempotent (verified via PRE retrieve).
- `Opportunity-npsp__Membership Layout` had the dates at Edit → SELECTED to prove the live Edit→Required
  transition + that setFieldBehavior works on a MANAGED (npsp) layout.
- Layout retrieve requires the NAMESPACED fullName (list-metadata strips the namespace); the non-namespaced
  name returns "cannot be found".

## Attestation note
Record Type (RecordTypeId) cannot be tracked via metadata replay (SF refuses) → MANUAL handoff. On illinois
RecordTypeId was already tracked; the op never touched it (exclusive enumerates only automatable fields).
Attested via POST /handoff (attesting-without-executing, test workspace) on explicit QA instruction.
