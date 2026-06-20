# Sandbox handoff — Aspen History 101 QA fixture en veevartd

Isolation prefix: `qa-IM-916-3f2318`
Sandbox: `veevartd` (Tucson Botanical Trainings)
Upserted: 2026-06-19T21:54:33Z (bulk job 750W400000ayWEqIAM, 5/5 success)

## 5 Contacts a verificar manualmente

| # | Nombre | External ID (Aspen REGISTRANT.LOOKUPID) | Salesforce Id | Lightning URL | Screenshot esperado |
|---|---|---|---|---|---|
| 1 | Alan Becker | `qa-IM-916-3f2318-evreg-10005531` | `003W400000zpmtuIAA` | [https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmtuIAA/view](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmtuIAA/view) | `attachments/tr-073-tc-64/scenario-11/contact-1-becker.png` |
| 2 | Stevens Loomis | `qa-IM-916-3f2318-evreg-10005532` | `003W400000zpmtwIAA` | [https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmtwIAA/view](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmtwIAA/view) | `attachments/tr-073-tc-64/scenario-11/contact-2-loomis.png` |
| 3 | William Von Stocken | `qa-IM-916-3f2318-evreg-10005533` | `003W400000zpmtvIAA` | [https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmtvIAA/view](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmtvIAA/view) | `attachments/tr-073-tc-64/scenario-11/contact-3-von-stocken.png` |
| 4 | Jessica Sanow | `qa-IM-916-3f2318-evreg-10005534` | `003W400000zpmttIAA` | [https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmttIAA/view](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmttIAA/view) | `attachments/tr-073-tc-64/scenario-11/contact-4-sanow.png` |
| 5 | Karen Day | `qa-IM-916-3f2318-evreg-10005535` | `003W400000zpmtxIAA` | [https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmtxIAA/view](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/r/Contact/003W400000zpmtxIAA/view) | `attachments/tr-073-tc-64/scenario-11/contact-5-day.png` |

## Vista de lista filtrada

1. Abrir [Contacts list view](https://tucsonbotanical--trainings.sandbox.my.salesforce.com/lightning/o/Contact/list?filterName=__Recent)
2. En el search box pegar: `qa-IM-916-3f2318`
3. Verificar que aparecen los 5 Aspen attendees (Becker, Day, Loomis, Sanow, Von Stocken)
4. Guardar screenshot en `attachments/tr-073-tc-64/scenario-11/list-view-5-contacts.png`

## Qué validar visualmente

- Los 5 Contacts existen y son visibles en Lightning
- Cada Contact tiene Description con el tag `QA fixture qa-IM-916-3f2318 | Aspen History 101 pre-registration`
- El External ID Auctifera__Implementation_External_ID__c contiene el REGISTRANT.LOOKUPID original de Aspen (evreg-1000553x)
- Karen Day corresponde al spot-check evreg-10005535 (Scenario 10 del TR)

## Aclaración importante (para dev / operator)

Estos 5 records son **QA fixtures**, no un load real de migration. Reproducen la forma esperada del PR #135 (5 standalone pre-registration registrants de Aspen History 101) en una sandbox accesible (Tucson Botanical, no Aspen). El prefijo `qa-IM-916-3f2318` permite identificarlos y borrarlos sin tocar data real.

## Rollback

Cuando termines las screenshots:
```bash
sf data query --target-org veevartd --query "SELECT Id FROM Contact WHERE Auctifera__Implementation_External_ID__c LIKE 'qa-IM-916-3f2318-%'" --result-format csv > /tmp/qa-IM-916-rollback.csv
sf data delete bulk --target-org veevartd --sobject Contact --file /tmp/qa-IM-916-rollback.csv --wait 5
```
