# TR-074 · TC-65 · Screenshot capture guide

Bundle del **Deliverable 2** (curated master · 3 ICs) en modo **functional UI review**.
Sandbox validation omitida por pedido del usuario — toda la evidencia es UI / Network /
SOQL desde la app Implementations en **AWS dev** contra **`im696-tucson` (Tucson
Botanical `--veevartd`)**.

## Setup mínimo antes de capturar

1. Login Cognito en la app Implementations (AWS dev).
2. Confirmar org `im696-tucson` activa en Connect Org (chip healthy).
3. Plan Preview accesible con el catálogo seeded.
4. DevTools (Network + DOM inspector) abierto en todos los scenarios con tráfico API o
   validación de componente.
5. Terminal con `sf` autenticado contra `im696-tucson` para los SOQL post-checks
   (Scenarios 12-15).

## Convenciones

- Cada screenshot va en `attachments/tr-074-tc-65/scenario-<N>/<id>-<phase>-<descr>.png`.
- El `<id>` está numerado por step (1, 2, 3...). Si un step pide múltiples capturas, se
  usa el sufijo `a`, `b`, `c` (e.g. `02a-when-form-filled.png`).
- Naming de archivo en kebab-case, prefijo con phase (`given`, `when`, `then`).
- Resolución mínima 1280x720; ZIPear si pesa > 2 MB.

## Mapa scenario → AC → ticket

| # | Scenario | AC Notion | Ticket fuente |
|---|---|---|---|
| 1-3 | Operator input free-text | D2 · Feature 1 | IM-745 |
| 4-5 | Discovered-choice select | D2 · Feature 2 | IM-744 P2 |
| 6-8 | MANUAL handoff lifecycle + card render | D2 · Feature 3 | IM-744 P3, IM-753 |
| 9 | Failure-cause surfacing | D2 · Feature 4 | transversal (IM-758) |
| 10-11 | Plan Preview FE | D2 · Feature 5 | IM-744 FE |
| 12-15 | Case 4.01 picklist + funds + idempotency | D2 · Feature 6 | IM-918 |
| 16 | General Donation Fund IC end-to-end | D2 · Feature 6 anchor | IM-917 |
| 17-19 | Manual-tier catalog broad sweep | D2 · Feature 7 | IM-953 |

## Tras capturar todos los screenshots

1. Drop los PNGs en sus paths exactos (los listados en `tr-074-tc-65.testrun.yml`).
2. Editar el TR para flipear cada step a `status: passed` (o `failed` + abrir defect).
3. Recalcular el `summary` (los counts de passed/failed/notRun + `passRate`).
4. Agregar history entry `to: completed` con timestamp real de cierre.
5. Commit + push a main para que TestManager re-ingeste.

## Riesgos abiertos a tener en mente al capturar

- **Handoff PR aún Draft** — validar el lifecycle park → attest → resume, NO mutaciones
  reales del org detrás del handoff.
- **Polling, no WebSocket** — esperar ~5s entre cambios de estado para el refetch.
- **T2 page-layout y per-IC isolation se movieron a D3** — NO levantar como bugs aquí.
- **Legacy `HandoffSession` card preservada** — el inline "Mark as done" sólo aplica
  a `type: "handoff"` con `note`.
- **Case 4.01 Axis B=70** — la lista de debit funds → PM necesita confirmación con dev
  (CSV plain-text vs HTML disagree).
- **IM-953 sweep en prod** — read-only, no alterar PlanRuns existentes.
