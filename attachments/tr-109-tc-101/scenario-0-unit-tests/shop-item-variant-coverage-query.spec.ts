import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Locks the IM-1005 variant-coverage contract that is split across three queries:
 *   - sale_item.sql emits an Item_Variant FK for EVERY sold variant, active or not,
 *     so item_variant.sql must emit a superset: no ISACTIVE row filter. Inactive
 *     variants arrive unsellable (ISACTIVE drives the availability flags).
 *   - stock_replenishment_order.sql deliberately keeps its ISACTIVE = 1 filter, so
 *     inactive variants never receive stock. Their historical Sold items would trip
 *     Veevart's "Out of Stock" validations unless Bypass_Stock__c is set: on the
 *     variant when inactive, and on the catalog item when the product has no active
 *     non-primary variant (Number_of_variants2__c counts only those) but does have
 *     inactive variants with sale lines.
 * If the ISACTIVE filter returns, the regression only surfaces as FK failures in a
 * future customer load — exactly how IM-1005 happened.
 *
 * External contract note: the bypass predicates mirror Salesforce-side artifacts that
 * live outside this repo — the Number_of_variants2__c rollup (Auctifera
 * CatalogItemTriggerHandler.rollUpNumberOfVariants) and the Total_stock_validation /
 * Total_stock_validation2 rules. This spec locks only the SQL text; drift in those
 * artifacts is caught by pre-load sandbox validation, not CI.
 *
 * Assertions run against whitespace-normalized SQL (runs of whitespace collapsed to
 * one space) so a behavior-preserving reformat cannot fail the contract.
 */
const normalize = (sql: string): string => sql.replace(/\s+/g, ' ');

describe('shop item variant migration — inactive-coverage contract', () => {
  const shopDir = join(__dirname, '..', 'queries', 'shop');
  const readNormalized = (file: string): string =>
    normalize(readFileSync(join(shopDir, file), 'utf8'));

  const itemVariant = readNormalized('item_variant.sql');
  const catalogItem = readNormalized('catalog_item.sql');
  const saleItem = readNormalized('sale_item.sql');
  const stockReplenishment = readNormalized('stock_replenishment_order.sql');

  describe('item_variant.sql', () => {
    it('does not filter variants by ISACTIVE (sale items reference inactive ones)', () => {
      expect(itemVariant).not.toMatch(/WHERE pi\.ISACTIVE/i);
    });

    it('keeps inactive variants unsellable via the availability flags', () => {
      expect(itemVariant).toContain(
        'pi.ISACTIVE AS Auctifera__Available_Collection_Online__c',
      );
      expect(itemVariant).toContain(
        'pi.ISACTIVE AS Auctifera__Available_for_sale__c',
      );
    });

    it('bypasses stock on inactive variants (no replenishment rows exist for them)', () => {
      expect(itemVariant).toMatch(
        /CASE WHEN pi\.ISACTIVE = 1 THEN 0 ELSE 1 END AS Auctifera__Bypass_Stock__c/,
      );
    });
  });

  describe('catalog_item.sql', () => {
    it('gates product bypass on active NON-PRIMARY variants, mirroring the Number_of_variants2__c rollup', () => {
      expect(catalogItem).toMatch(
        /pi_active\.ISACTIVE = 1 AND pi_active\.SEQUENCEID <> 1/,
      );
    });

    it('bypasses stock only when unbacked sales exist (inactive variants with sale lines)', () => {
      expect(catalogItem).toMatch(
        /pi_inactive\.ID.*?pi_inactive\.ISACTIVE = 0/,
      );
      expect(catalogItem).toContain(
        'soim_hist.MERCHANDISEPRODUCTINSTANCEID = pi_inactive.ID',
      );
    });
  });

  describe('cross-query contract', () => {
    it('sale_item.sql joins variants without an ISACTIVE condition', () => {
      expect(saleItem).toContain('pi.ID = soim.MERCHANDISEPRODUCTINSTANCEID');
      expect(saleItem).not.toMatch(/pi\.ISACTIVE/);
    });

    it('stock_replenishment_order.sql keeps its ISACTIVE filter (inactive stock must not inflate inventory)', () => {
      expect(stockReplenishment).toMatch(/WHERE pi\.ISACTIVE = 1/i);
    });
  });
});
