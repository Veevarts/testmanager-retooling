# AC3 · Recommended default batchScope=200 — DEFERRED to IE run

Uses the same PRE-baseline as AC2 (`scenario-2/illinois-PRE-baseline.json`,
0 jobs LAST_N_DAYS:7).

## Pending from you (Evans / IE handoff)

To close AC3 with source-side evidence:

1. Open the MigrationApp UI on illinois-trainings.
2. Trigger the plan `ic-3-22-pos-batches` (v4) — SEPARATE run from AC2.
3. When the run parks in AWAITING_INPUT for step 1, **enter `batchScope = 200`
   (or accept the recommended default 200)**.
4. Wait for the step to complete.
5. Notify QA — I re-run the AsyncApexJob query and confirm:
   - A new `AsyncApexJob` row exists (distinct from AC2's row by CreatedDate).
   - Status in accepted state.
   - Effective scope = 200 (via logs if available).

## Nota sobre BATCH_SCOPE default = 200

El ticket flaggea que el default 200 está **unconfirmed by PM** (decision
confidence 70). Este scenario valida el mecanismo del default, no la decisión
final del valor. Si PM confirma un default distinto (por ejemplo 500), el spec
v4 puede actualizar el `placeholder` sin cambio de contrato: el input sigue
siendo required number con range 1-2000.

Status: `not-run` — deferred to IE run.
