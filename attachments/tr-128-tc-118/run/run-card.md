# IE Run Card — IC 5.04 Opportunity Stages / businessProcess op (TR-128 / TC-118)

- **caseId**: `ic-5-04-opportunity-stages` **v2** (feasibility `auto`)
- **PR under test**: Veevarts/MigrationAppBackend#263 (MERGED 2026-07-16, merge `ed3da574`, base `82c35b14`) — CODE PR (+1736/-20, new T3 businessProcess op)
- **org**: illinois-trainings — `orgId=00DWI00000CIwZi2AL` (NPSP present; 0 Opportunity record types / 0 sales processes PRE)
- **path**: A (API-driven) — Cognito admin session

## Primary evidence = jest code-contract (org-independent)
- clone @ merge `ed3da574`, npm ci clean
- 4 touched suites: **332 passed, 0 failed** (adapter.spec + handler.spec + metadata-mutation-spec.spec + ic-5-04 seed.spec)
- businessProcess op `-t` filter: **17 passed, 0 failed** (covers author+ensure, update-in-place no-dup, idempotent, dynamic RT resolution, optional tolerate-absent, required-fails-when-absent, assignToRemaining excludes MANAGED RTs, validation rejects)
- tsc --noEmit clean · eslint clean on touched files
- genuinely-new: base=0 op markers (stageValues/assignToRemaining/BusinessProcessSpec/'businessProcess'), merge=6/7/2/11

## Live authoring (partial, illinois)
- Run 1: `f1e35f79-e74a-43a5-b4bb-15d797354bd2` — completed 1/1 done, 0 failed
- Run 2 (idempotency): `fad79425-97da-4638-84a8-ba5eae9f1bdf` — completed 1/1 done, 0 failed
- OpportunityStage: `Pledged` added active (10→11), stock preserved (add/activate-only)
- BusinessProcess (Metadata API list): NPSP_Default + Grants created (unmanaged), exactly 1 each after 2 runs (no dup), managed vnfp__NPSP_Default untouched
- RT-assign: Grant RT absent → optional skip (step done, didn't fail) = live tolerate-absent; assignToRemaining (0 unmanaged RTs) no-op

## Lens note (important)
The Tooling API `BusinessProcess` sObject returns 0 for these processes (known SF blind spot for
standard-object BusinessProcess). The AUTHORITATIVE lens is `sf org list metadata -m BusinessProcess`,
which confirms Opportunity.NPSP_Default + Opportunity.Grants exist (unmanaged). Do NOT read the Tooling
0 as a defect. Standalone source retrieve of standard-object BusinessProcess also returns empty
(retrievable only within the CustomObject) — existence + no-dup via list-metadata + the op's own
read-back (step done) + the jest authoring test cover the stage ordering.

## Org-gap (honest)
illinois has NPSP but 0 Opportunity record types → assignToRemaining to real RTs + managed-RT-skip
NOT reproducible live; covered by the 17 jest unit tests + the dev's CamiloDevOrg verification.
