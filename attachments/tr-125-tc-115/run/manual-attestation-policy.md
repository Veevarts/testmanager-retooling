# IM-1075 / TC-114 · Manual-step attestation policy

**User instruction VERBATIM (2026-07-24):** "revisa la memoria, todos los handoff se deben finalizar"

Grounded in memory `reference-migrationapp-ie-run-automation.md` lines 63/74/76: the
**"Test IM cases Org Tucson"** workspace (this run: clientId `cdff34f1-9774-41b0-a6a3-124bc03d11cb`,
org `00DWI00000CIwZi2AL` = illinois-trainings) permits **ATTESTING-WITHOUT-EXECUTING** on MANUAL
steps for QA validation runs, **on explicit QA instruction**. The escape hatch to the
"never auto-attest" guardrail is satisfied by the user's explicit instruction above.

**Action:** attest steps 13-17 via `POST /implementations/plan-runs/<id>/steps/<templateId>/<stepId>/handoff`
sequentially as each reaches `blocked-human`, until the run reaches `completed` (17/17 done, 0 blocked).

**Integrity note:** the actual UI edits (layout buttons, POS/Ticketing Lightning overrides,
Lightning Record Page org defaults, Exhibition/Event record page edit, compact layout clone) are
NOT performed by the harness — this is attesting-without-executing, the documented pattern for the
test workspace. AC5 (manual handoff) is validated on: (a) each step correctly parked as MANUAL with
its step-by-step guide, (b) attested per explicit QA instruction. For a real customer org the manual
work would be executed by the IE before attestation.
