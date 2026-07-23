import { parseSpec } from '@/implementations/infrastructure/seeds/publish-plan-template.cli';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Lockstep test for the case-3.22 seed JSON (Drawer Control Batch & POS Purchase
 * Payment Propagation Batch). 3.22 is a HYBRID case: one AUTOMATED T6 step
 * enqueues the POS Purchase Payment Propagation batch, one MANUAL handoff runs
 * the Cashier Drawer Control batch (whose no-arg constructor is `public`, not
 * `global`, so it is not anon-Apex-callable — verified in AuctiferaDX).
 *
 * Pins the v4 surface introduced by IM-1079:
 *  - the batch chunk size is a REQUIRED `number` operator input (`batchScope`,
 *    range 1-2000, recommended default 200) — NOT the old hardcoded
 *    `BATCH_SCOPE = 200` constant. Dropping the token/declaration or
 *    re-hardcoding the scope would silently ship;
 *  - the batch is launched via the real global Auctifera class
 *    `Auctifera.POSPurchasePaymentPropagationBatch` (org-agnostic — no hardcoded
 *    Id / org-specific class);
 *  - the enqueue is verified through an AsyncApexJob query-back (accepted state).
 */
describe('ic-3-22-pos-batches.json', () => {
    const raw = JSON.parse(
        readFileSync(resolve(__dirname, 'ic-3-22-pos-batches.json'), 'utf8'),
    ) as unknown;

    it('parses against the publish-plan-template CLI schema (v4, hybrid)', () => {
        const spec = parseSpec(raw);
        expect(spec.case.caseId).toBe('ic-3-22-pos-batches');
        expect(spec.case.version).toBe(4);
        expect(spec.case.feasibility).toBe('hybrid');
    });

    it('keeps case.version and template.version in lockstep (append-only single-case template must publish the current case version)', () => {
        const spec = parseSpec(raw);
        expect(spec.template.version).toBe(spec.case.version);
    });

    it('has 2 ordered steps: AUTOMATED T6 enqueue -> MANUAL drawer-control handoff', () => {
        const spec = parseSpec(raw);
        expect(spec.steps).toHaveLength(2);
        const [s1, s2] = spec.steps;
        expect([s1.order, s2.order]).toEqual([1, 2]);
        expect(s1.kind).toBe('AUTOMATED');
        expect(s1.toolName).toBe('T6');
        expect(s2.kind).toBe('MANUAL');
    });

    it('launches the batch via the real global Auctifera class, verified by AsyncApexJob query-back', () => {
        const spec = parseSpec(raw);
        const apex = (spec.steps[0].inputPayload as { apex: string }).apex;
        // Org-agnostic launch: the namespaced global batch class, NOT a
        // hardcoded Id or org-specific class.
        expect(apex).toContain(
            'new Auctifera.POSPurchasePaymentPropagationBatch()',
        );
        expect(apex).toContain('Database.executeBatch');
        // Enqueue is verified (AsyncApexJob accepted state), not batch completion.
        expect(apex).toContain('FROM AsyncApexJob');
    });

    it('exposes the batch chunk size as a REQUIRED number operator input (batchScope, 1-2000)', () => {
        const spec = parseSpec(raw);
        const payload = spec.steps[0].inputPayload as {
            apex: string;
            requiredInputs?: ReadonlyArray<{
                key: string;
                type: string;
                required?: boolean;
                constraints?: { min?: number; max?: number };
            }>;
        };
        // The scope MUST be the substituted token, NOT a re-hardcoded constant,
        // and coerced through Decimal.round so a decimal answer rounds instead of
        // throwing System.TypeException at Integer.valueOf.
        expect(payload.apex).toContain(
            "Integer.valueOf(Decimal.valueOf('{{batchScope}}').round())",
        );
        expect(payload.apex).not.toContain('BATCH_SCOPE = 200');
        const input = (payload.requiredInputs ?? []).find(
            (i) => i.key === 'batchScope',
        );
        expect(input).toBeDefined();
        expect(input?.type).toBe('number');
        expect(input?.required).toBe(true);
        expect(input?.constraints?.min).toBe(1);
        expect(input?.constraints?.max).toBe(2000);
    });
});
