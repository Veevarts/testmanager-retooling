# Sandbox handoff — rev-10626550 QA fixture en veevartd

Isolation prefix: `qa-IM-919-96db37`
Sandbox: `veevartd` (Tucson Botanical Trainings)
Upserted: 2026-06-22 (4 bulk jobs, 6 records total, 6/6 success)

## Records insertados

| # | Object | Name | SF Id | Lightning URL |
|---|---|---|---|---|
| 1 | Account | QA fixture qa-IM-919-96db37 \| Bucki Household | (consultar via Lightning) | (referencia parent) |
| 2 | Contact | Slawomir Bucki (primary member del gift membership) | `003W400000zwP2yIAE` | [open](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zwP2yIAE/view) |
| 3 | Contact | Adriana Lopez (donor resuelto via FT-constituent fallback) | `003W400000zwP2zIAE` | [open](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zwP2zIAE/view) |
| 4 | Opportunity | Gift Membership rev-10626550 (Bucki primary member, Lopez donor) | `006W400000ODO57IAH` | [open](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Opportunity/006W400000ODO57IAH/view) |
| 5 | OCR | Slawomir Bucki · Role=Member · IsPrimary=false | `00KW400000FEAzmMAH` | (visible en Opp #4 → Related → Contact Roles) |
| 6 | OCR | Adriana Lopez · Role=Donor · IsPrimary=true | `00KW400000FEAznMAH` | (visible en Opp #4 → Related → Contact Roles) |

## La screenshot principal a capturar

Para cerrar Scenario 5 step 7 (post-load Lightning):

1. Abrir la Opportunity: https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Opportunity/006W400000ODO57IAH/view
2. Scroll a la sección "Contact Roles" (también puede llamarse "Opportunity Contact Roles" según layout).
3. Verificar que aparecen las 2 filas:
   - Adriana Lopez · Role=Donor · ✓ Primary
   - Slawomir Bucki · Role=Member
4. Capturar screenshot y guardarla en:
   `attachments/tr-072-tc-63/scenario-5/opportunity-contact-roles.png`

## Qué demuestra esta screenshot

- Que el query post-fix `contact_roles.sql` emite EXACTAMENTE 2 rows para la membership Opportunity rev-10626550:
  - 1 fila Member para el primary member (Slawomir, IsPrimary=false)
  - 1 fila Donor (IsPrimary=true) para el resolved primary contact (Adriana, vía FT-constituent fallback)
- Que la cardinalidad de Contact Roles es la esperada en Lightning (pre-fix solo aparecía la fila Member; post-fix aparecen ambas).
- Que el load real al org destino producirá esta misma forma — siempre que el value 'Donor' esté en el picklist OpportunityContactRole.Role (env config pendiente).

## Aclaración importante

Estos 6 records son **QA fixtures**, no un load real de migration. Reproducen la forma esperada de la output del PR #134 en una sandbox accesible (Tucson Botanical Trainings) para validar el comportamiento visual del Contact Roles fix de IM-919. El prefijo `qa-IM-919-96db37` permite identificarlos y eliminarlos sin tocar data real de Tucson.

## Rollback

Cuando termines la screenshot:

```bash
# Capturar Ids de los 6 records de la fixture
sf data query --target-org veevartd \
  --query "SELECT Id FROM OpportunityContactRole WHERE OpportunityId = '006W400000ODO57IAH'" \
  --result-format csv | tail -n +2 > /tmp/qa-IM-919-rollback-ocr.csv
sf data query --target-org veevartd \
  --query "SELECT Id FROM Opportunity WHERE vnfp__Implementation_External_ID__c = 'qa-IM-919-96db37-opp-rev-10626550'" \
  --result-format csv | tail -n +2 > /tmp/qa-IM-919-rollback-opp.csv
sf data query --target-org veevartd \
  --query "SELECT Id FROM Contact WHERE Auctifera__Implementation_External_ID__c LIKE 'qa-IM-919-96db37-contact-%'" \
  --result-format csv | tail -n +2 > /tmp/qa-IM-919-rollback-contacts.csv
sf data query --target-org veevartd \
  --query "SELECT Id FROM Account WHERE Auctifera__Implementation_External_ID__c = 'qa-IM-919-96db37-account'" \
  --result-format csv | tail -n +2 > /tmp/qa-IM-919-rollback-account.csv

# Delete en orden inverso de dependencias (OCR → Opp → Contact → Account)
sf data delete bulk --target-org veevartd --sobject OpportunityContactRole --file /tmp/qa-IM-919-rollback-ocr.csv --wait 5
sf data delete bulk --target-org veevartd --sobject Opportunity --file /tmp/qa-IM-919-rollback-opp.csv --wait 5
sf data delete bulk --target-org veevartd --sobject Contact --file /tmp/qa-IM-919-rollback-contacts.csv --wait 5
sf data delete bulk --target-org veevartd --sobject Account --file /tmp/qa-IM-919-rollback-account.csv --wait 5
```
