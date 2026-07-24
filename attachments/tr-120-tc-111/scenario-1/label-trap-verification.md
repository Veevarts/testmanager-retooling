# Label-trap verification — illinois-trainings (scenario 1, TC-111)

Live `sf sobject describe --target-org illinois-trainings` filtered to the Total / Paid_Value label-trap families on Client Purchases. Confirms the spec targets the non-formula storage field and avoids the DEPRECATED formula twins.

## Auctifera__ClientPurchase__c — Total family (DOUBLE trap)

| API name | Label | calculated | Notes |
|---|---|---:|---|
| `Auctifera__Total2__c` | Total | false | ← **spec target** (storage, trackable) |
| `Auctifera__Total__c` | (DEPRECATED) Total | true | formula twin #1 |
| `Auctifera__Total_Amount__c` | (Deprecated) Total | true | formula twin #2 |

Two distinct fields both carry a "(Deprecated) Total" label; only `Total2__c` is the live storage field. A bare-API-name approach would be ambiguous — the runtime `{anyOf:['Total2__c'], label:'Total'}` matcher lands deterministically on the storage field.

## Auctifera__ClientPurchase__c — Paid_Value family

| API name | Label | calculated | Notes |
|---|---|---:|---|
| `Auctifera__Paid_Value__c` | Amount Received | false | ← **spec target** (storage) |
| `Auctifera__Paid_Value1__c` | Paid Value | true | formula trap (PR body: "not Paid_Value1__c 'Paid Value'") |

## Verdict

- `Total2__c` (calc=false) is the trackable storage field; both deprecated Total twins are formulas (calc=true).
- `Paid_Value__c` (calc=false, label "Amount Received") is the target; `Paid_Value1__c` (calc=true, label "Paid Value") is the trap.
- `Shopify_Product_Id__c` present on CatalogItem as required matcher (closes IM-935).
- The runtime matcher resolves all traps correctly, confirmed by the live run (POST-verify shows Total2/Paid_Value tracked).

Reproduction:
```bash
sf sobject describe -s Auctifera__ClientPurchase__c --target-org illinois-trainings --json | jq '.result.fields[] | select(.name | test("Total|Paid_Value")) | {name, label, calculated}'
```
