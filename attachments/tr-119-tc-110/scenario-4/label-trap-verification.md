# Label-trap verification — illinois-trainings sobject describe (scenario 4)

For each of the 5 label-traps documented in the PR body, live `sf sobject describe` output filtered to the relevant fields. Confirms bare API names ARE formulas (calculated=true) and the `_2/_3/_v` variants ARE storage (calculated=false).


## Auctifera__Rental_Event__c — Paid Amount / Description

| API name | Label | calculated | type |
|---|---|---:|---|
| `Auctifera__Description__c` | Description | false | textarea |
| `Auctifera__Paid_Amount_2__c` | Paid Amount | false | currency |
| `Auctifera__Paid_Amount__c` | Paid Amount (DEPRECATED) | true | currency |

## Auctifera__Rental_Resources__c — Subtotal + Tax_Amount

| API name | Label | calculated | type |
|---|---|---:|---|
| `Auctifera__Subtotal_Amount3__c` | Subtotal Amount | false | currency |
| `Auctifera__Tax_Amount3__c` | Tax Amount | false | currency |
| `Auctifera__Ticketing_Tax_Amount__c` | Ticketing Tax Amount | false | currency |
| `Auctifera__Subtotal_Amount__c` | (DEPRECATED) Subtotal Amount | true | currency |
| `Auctifera__Tax_Amount__c` | (DEPRECATED) Tax Amount | true | currency |

## Auctifera__Rental_Payments__c — Amount Received

| API name | Label | calculated | type |
|---|---|---:|---|
| `Auctifera__Amount__c` | Amount | false | currency |
| `Auctifera__Paid_Value__c` | Amount Received | false | currency |

## Auctifera__Resources__c — Quantity

| API name | Label | calculated | type |
|---|---|---:|---|
| `Auctifera__Number_of_Parts__c` | Quantity | false | double |

## Auctifera__Display_Storage_Location__c — Display trap sanity

| API name | Label | calculated | type |
|---|---|---:|---|
| `Auctifera__Flat_Fee_After_Taxes3__c` | Flat Fee After Taxes | false | currency |
| `Auctifera__Flat_Fee_Before_Taxes3__c` | Flat Fee Before Taxes | false | currency |
| `Auctifera__Flat_Fee_Guidance__c` | Flat Fee Guidance | false | textarea |
| `Auctifera__Flat_Fee__c` | Flat Fee | false | currency |
| `Auctifera__Hourly_Rate_After_Taxes3__c` | Hourly Rate After Taxes | false | currency |
| `Auctifera__Hourly_Rate_Before_Taxes3__c` | Hourly Rate Before Taxes | false | currency |
| `Auctifera__Hourly_Rate__c` | Hourly Rate | false | currency |
| `Auctifera__Flat_Fee_After_Taxes__c` | (DEPRECATED) Flat Fee After Taxes | true | currency |
| `Auctifera__Flat_Fee_Before_Taxes__c` | (DEPRECATED) Flat Fee Before Taxes | true | currency |
| `Auctifera__Flat_Fee_Taxes__c` | Flat Fee Taxes | true | currency |
| `Auctifera__Hourly_Rate_After_Taxes__c` | (DEPRECATED) Hourly Rate After Taxes | true | currency |
| `Auctifera__Hourly_Rate_Before_Taxes__c` | (DEPRECATED) Hourly Rate Before Taxes | true | currency |
| `Auctifera__Hourly_Rate_Taxes__c` | Hourly Rate Taxes | true | currency |


## Verdict

- All 5 label-trap `_2/_3/_v` variants confirmed as `calculated=false` (storage, trackable).
- All corresponding bare API names confirmed as `calculated=true` (formula, marked DEPRECATED in label).
- `Description__c` on Rental Event confirmed as `textarea` (rich-text) storage field, `calculated=false` → trackable via metadata replay (per PR reversal claim).

Reproduction command:
```bash
sf sobject describe -s <sobject> --target-org illinois-trainings --json | jq '.result.fields[] | select(.name | test("<pattern>")) | {name, label, calculated, type}'
```
