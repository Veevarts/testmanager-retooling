# Scenario 1 evidence — static contract + seed fidelity + CSV byte-match + genuinely-new

## Op wiring (metadata-mutation-spec.ts, merge 3f13f082)
- `customObjectTranslation` added to `METADATA_MUTATION_OPS` (closed list) — confirmed by the spec test that asserts the exact ordered op list.
- Added to the `MetadataMutationSpec` union.
- New guard `isCustomObjectTranslationSpec`.
- New interfaces `CustomObjectFieldTranslationSpec`, `CustomObjectTranslationObjectSpec`, `CustomObjectTranslationSpec`.

## Deploy-not-CRUD (adapter t3-metadata.adapter.ts)
- `applyCustomObjectTranslation` builds a package zip (`jszip`) with `package.xml` + one `objectTranslations/<object>-<lang>.objectTranslation` per object, calls `conn.metadata.deploy(buffer, {singlePackage:true, rollbackOnError:true})`, polls `checkDeployStatus` (bounded maxPolls=40 × 2000ms = 80s < 120s Lambda timeout), then verifies via `queryFieldLabelByName` (FieldDefinition.Label) — NOT `metadata.read` (never surfaces default-language field overrides).
- The adapter NEVER calls `metadata.update` for this op — asserted by adapter test 1: `expect(deploy).toHaveBeenCalledTimes(1); expect(update).not.toHaveBeenCalled();`.
- `jszip` moved dev → prod dependency (package.json + package-lock.json).

## Genuinely-new proof
```
adapter 'customObjectTranslation' refs:  merge-base ed3da574 = 0   →   merge 3f13f082 = 37
seed ic-6-01-override-field-labels.json:  merge-base = version 1 / feasibility manual / kind MANUAL
                                          merge      = version 2 / feasibility auto   / kind AUTOMATED (toolName T3)
```

## Seed fidelity — AC delivery table + CSV Order 6.01 byte-match (v2 as delivered by #264)
The v2 seed (PR #264) declares 4 objects / 10 field-label overrides, matching the AC feature-2 delivery table AND the CSV `Implementation_Case__c` Order 6.01 (a185w00000trMOzAAM) playbook byte-for-byte:

| Object | Field | Override | AC | CSV |
|---|---|---|---|---|
| Group_Reservation | Account | Household/Organization | ✓ | ✓ |
| Museum_Offer_Item | Group_Reservation (opt.) | Item | ✓ | ✓ |
| Museum_Offer_Item | Museum_Offer | Ticket Offer | ✓ | ✓ |
| Museum_Offer_Item | Museum_Offering_Price | Ticket Offer Price (after taxes) | ✓ | ✓ |
| Museum_Offer_Item | Museum_Offering_Subtotal | Ticket Offer Price (before taxes) | ✓ | ✓ |
| Museum_Offer_Item | Related_Exposition | Related Exhibition/Event | ✓ | ✓ |
| Museum_Offer_Item | Related_Exposition_Id | Related Exhibition/Event ID | ✓ | ✓ |
| Museum_Offer | Exposition | Exhibition/Event | ✓ | ✓ |
| POS_Purchase | Client | Client (Contact) | ✓ | ✓ |
| POS_Purchase | Client2 | Client (Household/Organization) | ✓ | ✓ |

## v2 → v3 delta (tracked follow-up #267, NOT drift)
`main` HEAD is v3: **9** overrides. PR **#267 "IM-1095b: IC 6.01 v3 — drop the Group & Reservation 'Item' override"** (commit `4f07e718`, merged 2026-07-16) intentionally removed the `Museum_Offer_Item.Group_Reservation → Item` override (the only `optional` one in v2) and dropped all `optional` flags (all 9 remaining are required). Consequence for traceability: the AC feature-2 delivery table (10 rows) is now 1 row ahead of the shipped spec (9). Intentional per #267 — surface to PM only for doc alignment, not a defect.
