# IM-1075 / TC-114 · IE run card — plan-run 6b31d90b-34da-404c-a97b-f6527fc6bd11

- caseId: ic-6-02-ticketing-page-layouts (LIVE catalog v4 == PR #247 v3 functional; v4 = IM-1090 #262 housekeeping bump, steps byte-identical except step1 description prose)
- client: cdff34f1-9774-41b0-a6a3-124bc03d11cb (workspace "Test IM cases Org Tucson")
- org: 00DWI00000CIwZi2AL (illinois-trainings / ilholocaustmuseum--trainings)
- started: 2026-07-24T23:05:09Z · startedBy: evansri.mondragonp@veevart.com
- plan: 1 case, 17 steps (12 AUTOMATED + 5 MANUAL)

## AC1 evidence (single park, live-discovered options)
Run parked AWAITING_INPUT with EXACTLY 10 layout selects on ONE card (single park, IM-928 lesson).
Each select carried live-discovered options with the org's real namespaced fullNames (vnfp__ / Auctifera__
reconstructed by the discovery adapter) — org/version-agnostic, no hardcoded fullName (Medium caveat resolved).
Option counts: ticketing=3, exhibitionEvent=7, ticketOffer=3, ticketItem=1, exhTimeCapacity=2,
posPurchase=3, charge=3, chargeItem=3, refund=1, refundItem=2.

## Operator layout selections (most-recent Veevart/VNFP per object, per spec label hints)
ticketingLayout            = vnfp__VNFP Ticket Layout - V12 - July 2024
exhibitionEventLayout      = vnfp__Ticketing Layout V4
ticketOfferLayout          = Auctifera__Museum Offer Layout - V2 - Aug 2023
ticketItemLayout           = Auctifera__Ticket Item Layout 2021-12  (only option)
exhibitionTimeCapacityLayout = Auctifera__Exhibition Time & Capacity Layout V2 202306
posPurchaseLayout          = vnfp__VNFP POS Purchase Layout - V3 - July 2024
chargeLayout               = vnfp__Charge Layout - V2 - November2024
chargeItemLayout           = vnfp__VNFP Charge Item Layout - V3 - April 2023
refundLayout               = Auctifera__Refund Layout  (only option)
refundItemLayout           = vnfp__VNFP Refund Item Layout - V2 - April 2023
