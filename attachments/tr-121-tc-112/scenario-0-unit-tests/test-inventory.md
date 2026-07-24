# Scenario 0 — jest code contract (27 dedicated tests, no-clone inventory from PR #264 diff @ 3f13f082)

CODE PR (10 files, +1383/-31). Test inventory read from the merge-commit diff (no local clone; `gh api contents?ref=3f13f082`). Not executed locally — MigrationAppBackend not cloned; verdict = static inventory + genuinely-new proof + live run. Dev gate (per PR body): jest/tsc/eslint green.

## t3-metadata.adapter.spec.ts — `describe('T3MetadataJsforceAdapter — customObjectTranslation')` (14)
1. DEPLOYS the resolved field-label override and verifies via FieldDefinition (default en_US) — `deploy` 1×, `update` NEVER; verifies operations applied; asserts the deployed `.objectTranslation` + package.xml members. **[deploy-not-CRUD core + AC op-S1]**
2. resolves a managed field by LABEL fallback when the anyOf API name misses. **[AC op-S3 resolution]**
3. deploys every object in ONE package (multi-object) and verifies each.
4. deploys ONLY the named field (blast-radius) — never touches the object's other labels (Status untouched). **[AC op-S2]**
5. is idempotent — re-applying an already-overridden label still verifies. **[AC op-S5]**
6. TOLERATES an optional field the org lacks — skips it (`skipped:true`), deploys the rest. **[AC op-S3 tolerate-absent]**
7. FAILS an unresolved NON-optional matcher (strict) and deploys nothing (`deploy` NOT called). **[AC op-S4]**
8. reports success=false with a Translation-Workbench hint when the override does not take (deployApplies=false) — detail matches /Translation Workbench/i and /en_US/. **[AC op-S6 precondition]**
9. reports success=false with the deploy error when the deploy fails ('language not active'). **[AC op-S6]**
10. reports success=false (never a false pass) when the deploy never completes — bounded poll gives up (≥40 checkDeployStatus calls). **[bounded-poll safety]**
11. surfaces MetadataDeployError when the deploy() call itself throws ('deploy failed to start').
12. surfaces MetadataDeployError when checkDeployStatus rejects mid-poll ('checkDeployStatus failed').
13. throws MALFORMED_REQUEST on an invalid language (not a locale key) — `deploy` NOT called.
14. throws MALFORMED_REQUEST on an empty objects list.

## t3-metadata.handler.spec.ts (8 param cases)
15. happy: `customObjectTranslation with matcher + exact-name field refs` (accepts anyOf matcher + exact API-name refs).
16–22. malformed rejections: empty objects list · object missing its object name · empty fields list · field missing a label · invalid spec-level language ('english') · invalid per-object language ('en-US') · field ref that is neither a name nor a matcher (`{}`).

## ic-6-01-override-field-labels.spec.ts (NEW file, 4)
23. parses against publish-plan-template CLI schema (v2, auto).
24. keeps case.version and template.version in lockstep.
25. has a single AUTOMATED T3 customObjectTranslation step (order 1, toolName T3, language en_US).
26. overrides the four objects with their resolved managed field labels (Group_Reservation/Museum_Offer_Item×6/Museum_Offer/POS_Purchase; the Group_Reservation→Item is `optional:true`).

## metadata-mutation-spec.spec.ts (1)
27. `isMetadataMutationSpec` boundary guard lists `customObjectTranslation` in the exact ordered op set.

## AC → evidence coverage matrix
| AC scenario | Covered by |
|---|---|
| op-S1 Deploy + verify (deploy-not-CRUD) | adapter #1 + LIVE (run done via deploy) |
| op-S2 Non-destructive (merge) | adapter #4 + LIVE blast-radius (Status + dropped Group_Reservation untouched) |
| op-S3 Tolerate absent + dynamic resolution | adapter #2, #6 |
| op-S4 Strict failure required-unresolved | adapter #7 |
| op-S5 Idempotent re-run | adapter #5 + LIVE (9/9 already at target re-verified) |
| op-S6 Precondition language/Workbench not active | adapter #8, #9 |
| e2e Run auto 6.01 end-to-end | LIVE run 0979a5fe (v3, 9 overrides, completed) + seed spec #23–26 |
