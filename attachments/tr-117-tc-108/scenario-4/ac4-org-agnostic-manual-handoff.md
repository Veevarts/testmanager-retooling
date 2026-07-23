# AC4 · Org-agnostic launch + Cashier Drawer Control manual handoff

## Static grep — hardcoded 18-char SF Ids in HEAD JSON spec

```
grep -oE '\b[a-zA-Z0-9]{18}\b' head-spec-v4.json | grep -v 'POSPurchasePayment|CashierDrawerContro'
→ 0 matches
```

**0 hardcoded 18-char SF Ids** in the entire HEAD spec (the only 18-char tokens
present are class names in `Auctifera.POSPurchasePaymentPropagationBatch` /
`Auctifera.CashierDrawerControlBatch`).

## Class references — namespace-prefixed, org-agnostic

```
grep -oE 'Auctifera\.[A-Z][A-Za-z]+' head-spec-v4.json | sort -u
Auctifera.CashierDrawerControlBatch
Auctifera.POSPurchasePaymentPropagationBatch
```

Both classes are referenced with the `Auctifera.` namespace prefix. The launch
call is:

```
Id jobId = Database.executeBatch(new Auctifera.POSPurchasePaymentPropagationBatch(), BATCH_SCOPE);
```

**No dynamic type binding, no reflection, no per-org class alias table.** As long
as the org has the Auctifera package installed with the global class visible, the
launch works identically across orgs.

## Cashier Drawer Control — MANUAL handoff

Step 2 in the HEAD JSON spec:

```
{
    "stepId": "run-cashier-drawer-control-batch-manual",
    "order": 2,
    "name": "Run the Cashier Drawer Control batch (manual)",
    "kind": "MANUAL"
}
```

`kind: MANUAL` — the runner does NOT attempt to launch this batch from anonymous
Apex. The spec description explains why:

> the Cashier Drawer Control batch cannot be triggered from anonymous Apex — its
> no-arg constructor is non-global in BOTH the Auctifera and vnfp namespaces
> (live probe on org im696-tucson returned 'Method is not visible: void
> Auctifera.CashierDrawerControlBatch.<init>()' and the same for vnfp), and the
> org ships no global schedulable wrapper for it.

The description then hands the IE a 4-step Lightning UI recipe:

> 1) App Launcher > search 'Veevart Settings' and open it.
> 2) Under 'Point of Sale (POS)' open 'Batches'.
> 3) On the 'Cashier Drawer Control' (a.k.a. Drawer Control) batch click 'Run'
>    (or 'Run & Schedule' to set a recurring schedule).
> 4) Confirm the batch was accepted (a job appears in Setup > Apex Jobs). Mark
>    this step done after the job is queued.

This is exactly the manual-handoff pattern documented in
`[[feedback-execute-auto-flag-manual]]` — never fake a PASS for what can't be
executed automatically.

## Org-specific patterns check

```
grep -oE '(https?://[^"]*|\.trainings\.[^"]*|--trainings\.sandbox)' head-spec-v4.json
→ 0 matches
```

No hardcoded URLs, no sandbox domains, no customer-specific references in the
HEAD spec.

## Verdict AC4

PASS static + spec-declared. The batch launch is org-agnostic (0 hardcoded IDs,
namespace-prefixed class refs, no org-specific patterns), and the Cashier Drawer
Control step is explicitly `MANUAL` with a documented UI-based handoff — no
attempt to auto-launch a non-global constructor.
