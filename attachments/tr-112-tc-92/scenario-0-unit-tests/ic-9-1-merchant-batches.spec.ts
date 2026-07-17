import { parseSpec } from '@/implementations/infrastructure/seeds/publish-plan-template.cli';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const occurrences = (haystack: string, needle: string): number =>
    haystack.split(needle).length - 1;

/**
 * Lockstep test for the case-9.1 seed JSON (Run Merchant Batches). 9.1 is an
 * `auto`, single-step T6 case that branches on the {{merchantType}} operator
 * input (Square | Stripe). The v4 bump fixes the QA-rejected (IM-939) Stripe
 * verify defect: the Stripe path used to fail a case (`FAILED`) whenever ANY
 * recent Square reconciliation AsyncApexJob existed in a bare 5-minute window,
 * which false-fails a Square->Stripe re-run on leftover rows from a prior Square
 * run or on rows the recurring Square crons fire in the same window. v4 replaces
 * that absolute scan with the snapshot/diff idiom (same as 9.3 step 2): snapshot
 * pre-existing Square job Ids, then assert no NEW (non-snapshot) Square row was
 * enqueued by this run. This spec pins that contract so a regression to the
 * absolute-scan form (or a version/feasibility drift) fails in CI, not on the
 * sandbox.
 */
describe('ic-9-1-merchant-batches.json', () => {
    const raw = JSON.parse(
        readFileSync(
            resolve(__dirname, 'ic-9-1-merchant-batches.json'),
            'utf8',
        ),
    ) as unknown;

    it('parses against the publish-plan-template CLI schema', () => {
        const spec = parseSpec(raw);
        expect(spec.case.caseId).toBe('ic-9-1-merchant-batches');
        expect(spec.case.version).toBe(4);
        expect(spec.case.feasibility).toBe('auto');
        expect(spec.case.category).toBe('BATCHES');
        expect(spec.template.templateId).toBe('ic-9-1-merchant-batches-tmpl');
        expect(spec.template.version).toBe(4);
    });

    it('has a single AUTOMATED T6 step branching on the {{merchantType}} select (Square | Stripe)', () => {
        const spec = parseSpec(raw);
        expect(spec.steps).toHaveLength(1);
        const [step] = spec.steps;
        expect(step.order).toBe(1);
        expect(step.kind).toBe('AUTOMATED');
        expect(step.toolName).toBe('T6');
        const input = (
            step.inputPayload as {
                requiredInputs?: ReadonlyArray<{
                    key: string;
                    type: string;
                    options?: readonly string[];
                }>;
            }
        ).requiredInputs?.[0];
        expect(input?.key).toBe('merchantType');
        expect(input?.type).toBe('select');
        expect(input?.options).toEqual(['Square', 'Stripe']);
    });

    it('Stripe verify snapshots pre-existing Square jobs and asserts NO NEW rows (v4 IM-939 fix)', () => {
        const spec = parseSpec(raw);
        const apex = (spec.steps[0].inputPayload as { apex: string }).apex;
        // Snapshot-before / diff-after: capture the pre-body Square job Ids, then
        // exclude them from the post-body check so only rows THIS run created can
        // fail the verify.
        expect(apex).toContain('Set<Id> priorSquareJobIds');
        expect(apex).toContain('AND Id NOT IN :priorSquareJobIds');
        expect(apex).toContain(
            'Stripe path must not enqueue Square batches but this run created',
        );
        // Both queries bind the SAME hoisted class list (single source of truth),
        // so the snapshot and diff populations cannot drift apart — a divergence
        // would silently re-open the IM-939 false-fail. Mirror of 9.3's
        // BATCH_SIMPLE_NAME constant.
        expect(apex).toContain(
            "final Set<String> SQUARE_BATCH_CLASSES = new Set<String>{ 'SquareChargeFixBatch', 'SquareRefundBatch' }",
        );
        expect(
            occurrences(apex, "'SquareChargeFixBatch', 'SquareRefundBatch'"),
        ).toBe(1);
        expect(occurrences(apex, 'ApexClass.Name IN :SQUARE_BATCH_CLASSES')).toBe(
            2,
        );
        expect(apex).not.toContain(
            "ApexClass.Name IN ('SquareChargeFixBatch', 'SquareRefundBatch')",
        );
        // The old absolute-scan form must be gone: the v3 straySquare scan with no
        // snapshot is exactly the false-positive QA rejected. Pin the full v3
        // message fragment, not a bare phrase that could collide with Square text.
        expect(apex).not.toContain('List<AsyncApexJob> straySquare');
        expect(apex).not.toContain('straySquare.size()');
        expect(apex).not.toContain('must not enqueue Square batches but found ');
    });

    it('Square path proves its own immediate jobs by captured Id and requires the durable flag + crons', () => {
        const spec = parseSpec(raw);
        const apex = (spec.steps[0].inputPayload as { apex: string }).apex;
        // Durable flag + the global Save-button scheduler (unchanged in v4).
        expect(apex).toContain('settings.Auctifera__Schedule_Square__c = true');
        expect(apex).toContain('new Auctifera.AutomaticBatchSchedule().execute(null)');
        // Immediate run captures the job Ids and verifies THOSE ids (correct
        // by-Id proof, not a recency scan).
        expect(apex).toContain(
            'Id chargeFixJobId = Database.executeBatch(new Auctifera.SquareChargeFixBatch()',
        );
        expect(apex).toContain(
            'Id refundJobId = Database.executeBatch(new Auctifera.SquareRefundBatch()',
        );
        expect(apex).toContain('WHERE Id IN (:chargeFixJobId, :refundJobId)');
        // Pure Apex DML — no callout / session-token use.
        expect(apex).not.toContain('/services/data');
        expect(apex).not.toContain('HttpRequest');
    });

    it('fails safely on an unrecognized merchant (no silent skip)', () => {
        const spec = parseSpec(raw);
        const apex = (spec.steps[0].inputPayload as { apex: string }).apex;
        expect(apex).toContain(
            "MERCHANT != 'square' && MERCHANT != 'stripe'",
        );
        expect(apex).toContain('unrecognized merchantType');
    });
});
