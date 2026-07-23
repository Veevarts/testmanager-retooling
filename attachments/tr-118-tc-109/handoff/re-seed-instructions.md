# Handoff — Master template dev/prod re-seed

**Status**: PENDING-CREDS (AWS SSO expired) · orchestrator-owned · out-of-scope-for-QA

**Owner**: pipeline orchestrator (dev/prod seed pipeline)

**Blocked by**: AWS SSO token refresh

## Pre-requisites

1. `Veevarts/MigrationAppBackend` cloned at `main` (post-merge, at or after commit `5c3e1aa`).
2. `npm ci` completed.
3. AWS SSO active for the pipeline account.

## Steps

1. Confirm dev target: `AWS_PROFILE=<dev-profile> aws sts get-caller-identity`.
2. Run: `npm run seed:master-template` (or the current wrapper — check `scripts/seed-master-template.ts` header).
3. Verify DynamoDB dev PlanTemplate.master:
   - `caseRefs.length === 76`
   - breakdown: `{ auto: 24, hybrid: 33, manual: 19 }`
   - `ic-veevart-auth` is ABSENT
   - `ic-4-05-transaction-journal-layouts` has `dependsOn: ['ic-4-01-specific-funds-debit-credit']`
   - `ic-8-02-resources-setup` has `dependsOn: ['ic-3-03-rename-tabs-and-labels']`
   - `caseRefs` are sorted ascending by `order`
4. Repeat against prod with `AWS_PROFILE=<prod-profile>`.
5. Comment on IM-1096 with:
   - Re-seed timestamps (dev + prod)
   - `caseRefs.length` observed
   - Link to seed run logs
   - Any deltas vs the 76/24/33/19 target

## Rollback path

If the re-seed produces an unexpected result (e.g., a caseRefs count != 76 or a
missing dependsOn edge): keep the previous master snapshot from DynamoDB and
restore. The pre-fix master had ~31 caseRefs (13 pinned + 18 manual after
EXCLUDE) — going back would drop the newly-included non-pinned cases from the
composed template until a fix is deployed.

## Reference

- QA sign-off: TR-118 (this run), scenarios 1-4 PASS.
- Scenario 5 stays `not-run` until this handoff completes.
- Once verified: reopen TR-118 + v2 commit flipping scenario 5 to `passed`
  (pattern: TR-115 / TR-116 / TR-117 v2 deep-dive).
