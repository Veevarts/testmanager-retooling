# Scenario 12 (TC-96 v3) — Functional UI evidence

## Executed 2026-07-03 via Playwright on scratch org `computing-power-944-dev-ed`

### Sequence

1. Login vía `test.salesforce.com` con credenciales pre-cargadas del scratch (username `test-cdnhu94l8bj2@example.com`).
2. Navegación a `/lightning/cmp/Auctifera__AddManageResourcesToRentalEvent?Auctifera__recordID=a1pdq00000HfuCX` (Rental Event "Rental NPS Test").
3. Screenshot pre-click: `01-pre-quicksave.png` — Lightning cmp cargado con Quick Save visible.
4. Click en **Quick Save**.
5. Screenshot post-click: `02-post-quicksave.png` — wizard avanzó al siguiente stage.
6. Captura del Network capture: `network-widget-wiring.txt`.

### Evidence obtenida — Widget wiring PASS

Playwright capturó la request outbound del widget:

```
GET https://surveytool.dev.veevart.ai/api/features/rentals/surveys
    ?clientOrgId=computing-power-944-dev-ed
    &respondentId=005dq00000NLWpIAAX
    &userCreatedDate=2026-07-01T15:58:58.000Z
    &today=2026-07-03
    &usageCount=2
```

Esto prueba:
- ✅ El widget está enganchado al Rentals Quick Save trigger en la scratch
- ✅ Todos los query params del eligibility contract están presentes: `clientOrgId`, `respondentId`, `userCreatedDate` (nuevo alias del PR #25/#27), `today`, `usageCount`
- ✅ `usageCount=2` incrementó desde `1` en TR-087 → el widget mantiene state de usage tracking

### Evidence bloqueada — Modal render

El request retornó `net::ERR_NAME_NOT_RESOLVED` en el Playwright Chromium context. Root cause dual:

1. **DNS split-horizon**: `surveytool.dev.veevart.ai` es host interno alcanzable desde el terminal local (curl funcionó en TR-097 scenarios 1-11) pero no desde el Chromium sandboxed de Playwright (posiblemente por DNS resolver diferente o falta de VPN en el contexto del browser).
2. **Respondent exhausted**: aún si el DNS resolviera, el running Salesforce user (`005dq00000NLWpIAAX`) es el mismo user que exhausted eligibility en TR-087 (mismo scratch). El general survey `id=8` tiene `onePerRespondent=true` según `triggerDetails`. Sin admin reset previo, el modal no renderizaría el general para ese user.

### Cómo completar el ciclo end-to-end

Manual desde tu browser (no Chromium sandboxed):

1. **Reset del respondent** vía admin cookie:
   ```bash
   curl -X DELETE "https://surveytool.dev.veevart.ai/api/admin/features/8/respondent-state/005dq00000NLWpIAAX" \
     -H "Cookie: <cognito-session>"
   ```
   O como IE logueado en `surveytool.dev.veevart.ai`, usar el admin UI (§Resetting Respondent State for QA en el doc QA-NPS-Survey-Tool.md).

2. **Re-abrir el Rental NPS Test** (misma URL de arriba) y hacer Quick Save.

3. **Capturar** desde tu browser:
   - `04-modal-title-general-survey.png` — modal abierto con `<h1>General Survey</h1>` (no "Rental NPS Test" ni "Rentals")
   - `05-modal-nps-question.png` — pregunta "How likely are you to recommend us to a friend or colleague?" con escala 1-10
   - `06-devtools-eligibility-response.png` (opcional) — DevTools Network mostrando el response body con `isGeneralSurvey:true, generalClientOrgId:"computing-power-944-dev-ed"`
   - `07-iframe-url.png` (opcional) — iframe URL preservando `surveyId + userCreatedDate`
   - `08-post-submit.png` (opcional) — estado post-submit del respondent

4. Drop los screenshots en este directorio (`attachments/tr-097-tc-96/scenario-12/`) y avisa para actualizar el TR.

### Verdict

- **PARTIAL PASS**: widget wiring end-to-end confirmed via Playwright network capture.
- **NOT-RUN (manual completion)**: modal render + title check + submit flow — bloqueado por DNS del Chromium + state exhausted del respondent. Requiere admin reset + repeat desde browser normal.
