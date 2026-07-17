import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { stripComments } from './sql-comment-utils';

// IM-694: the constituency export must mirror Altru's "Constituencies" tab.
// These guards fail if someone reverts to the old per-table union (which dropped
// system roles like Donor/Member/Patron and exported retired segmentation codes)
// or removes the external-ID dedup that keeps the Salesforce upsert key unique.
//
// Assertions run against comment-stripped SQL so the file's explanatory header
// (which discusses the old approach in prose) can be reworded without breaking
// the tests, and use whitespace-tolerant matches so a reindent is not a failure.
describe('constituency.sql', () => {
  const queryPath = join(
    __dirname,
    '..',
    'queries',
    'constituency',
    'constituency.sql',
  );
  const code = stripComments(readFileSync(queryPath, 'utf8'));

  it('sources the unified Altru constituency view instead of stitching per-role tables', () => {
    expect(code).toMatch(/FROM\s+V_QUERY_CONSTITUENCY\s+vq/i);

    // The old query hand-unioned these sources and hardcoded role labels; doing so
    // dropped every system constituency without a date-range table and mislabeled
    // tenant-renamed roles (e.g. Aspen's "Board Trustee").
    expect(code).not.toMatch(/BOARDMEMBERDATERANGE/i);
    expect(code).not.toMatch(/VOLUNTEERDATERANGE/i);
    expect(code).not.toMatch(/STAFFDATERANGE/i);
    expect(code).not.toMatch(/FUNDRAISERDATERANGE/i);
    expect(code).not.toMatch(/'Board Member'\s+AS\s+Constituency__c/i);
    expect(code).not.toMatch(/CONSTITUENCYCODE\s+cc/i);
  });

  it('excludes retired constituency definitions (inactive segmentation codes)', () => {
    // ISACTIVE mirrors CONSTITUENCYDEFINITION.ISACTIVE, so this drops retired
    // segments (HSDF/Spring) and tenant-disabled system roles from the export.
    expect(code).toMatch(/WHERE\s+vq\.ISACTIVE\s*=\s*1/i);
  });

  it('emits a deterministic external ID for system rows whose view ID is NULL', () => {
    expect(code).toMatch(/COALESCE\(/i);
    expect(code).toMatch(/CAST\(vq\.ID\s+AS\s+VARCHAR\(36\)\)/i);
    expect(code).toMatch(/'SYS_'/);
    expect(code).toMatch(/CAST\(vq\.CONSTITUENTID\s+AS\s+VARCHAR\(36\)\)/i);
    expect(code).toMatch(
      /CAST\(vq\.CONSTITUENCYDEFINITIONID\s+AS\s+VARCHAR\(36\)\)/i,
    );
  });

  it('guarantees external-ID uniqueness by collapsing rows that share the synthesized key', () => {
    // The synthesized key is coarser than the raw view grain; two ID-NULL rows for
    // the same (CONSTITUENTID, CONSTITUENCYDEFINITIONID) would otherwise emit a
    // duplicate Implementation_External_ID__c and fail the Salesforce upsert batch.
    expect(code).toMatch(
      /ROW_NUMBER\(\)\s+OVER\s*\(\s*PARTITION\s+BY\s+Implementation_External_ID__c/i,
    );
    expect(code).toMatch(/WHERE\s+RowRank\s*=\s*1/i);
  });

  it('carries the tenant-specific label and assignment date range through unchanged', () => {
    expect(code).toMatch(/vq\.CONSTITUENCY\s+AS\s+Constituency__c/i);
    expect(code).toMatch(/vq\.DATEFROM\s+AS\s+Date_From__c/i);
    expect(code).toMatch(/vq\.DATETO\s+AS\s+Date_To__c/i);
  });

  it('preserves the contact / organization / household routing', () => {
    expect(code).toMatch(/vq\.CONSTITUENTID\s*=\s*ct\.ID/i);
    expect(code).toMatch(/LEFT JOIN CONSTITUENTHOUSEHOLD ch ON/i);
    expect(code).toMatch(/ELSE ch\.HOUSEHOLDID/i);
    expect(code).toMatch(/ct\.ISCONSTITUENT\s*=\s*1/i);
  });
});
