-- Constituency migration (IM-694)
--
-- Business rule: Salesforce must receive exactly the constituency assignments a
-- user sees on the Altru constituent's "Constituencies" tab -- no more, no less.
--
-- Altru derives that list from TWO kinds of source:
--   1. Manually added constituencies stored in base CONSTITUENCY (+ code table).
--   2. System constituencies computed on the fly from the constituent's activity
--      (Donor, Loyal donor, Major donor, Member, Patron, Event registrant,
--      Major giving prospect, Individual, tenant-renamed Board Trustee, etc.).
--
-- The previous query only unioned base CONSTITUENCY plus four per-role date-range
-- tables. That produced two defects reported in IM-694:
--   * MISSING roles  -- every system constituency without a date-range table
--     (Donor, Member, Patron, Event registrant, prospect, Individual, ...) was
--     dropped. e.g. Aspen 104021 showed 13 in Altru but only 6 in Veevart.
--   * EXTRA roles    -- base CONSTITUENCY still holds retired/custom segmentation
--     codes (e.g. "HSDF 2023 Segment C", "Spring 2023 Segment D") that Altru
--     hides once the constituency definition is deactivated; the old query
--     exported them anyway. e.g. Tucson "Joan Grecchi" had 1 role in Altru but
--     showed 2 stale extras (and was missing the real one) in Veevart.
--   It also hardcoded the label 'Board Member', ignoring tenant renames such as
--   Aspen's 'Board Trustee'.
--
-- Fix: source the export from V_QUERY_CONSTITUENCY, the Blackbaud view that backs
-- the Altru constituency query/UI. It already unifies manual + system
-- constituencies at one logical row per assignment, with the exact grain, date
-- range, and tenant-specific label the UI shows.
--
-- Active-definition filter (WHERE vq.ISACTIVE = 1): safesql confirmed that
-- V_QUERY_CONSTITUENCY.ISACTIVE equals CONSTITUENCYDEFINITION.ISACTIVE for every
-- row (Tucson cross-tab: only True/True=133,640 and False/False=34,622 exist). So
-- ISACTIVE marks whether the tenant's constituency DEFINITION is active. Retired
-- definitions -- Tucson's "HSDF/Spring" segments AND Tucson's disabled "Event
-- registrant" -- are correctly excluded, while a tenant that keeps "Event
-- registrant" active (Aspen) still gets it. Validated reconciliations:
--   Tucson 22561 -> 2, Tucson Joan -> 1, Aspen 104021 -> 13 (all match the ticket).
--
-- Is_Active__c: definition-active is the inclusion gate, not a useful per-row
-- signal (every exported row would be "active"). We instead expose whether the
-- assignment itself is currently in effect -- open-ended (DATETO IS NULL) -- which
-- preserves the previous date-range roles' semantics and keeps historical,
-- date-ended roles (e.g. a former board member) flagged inactive but still
-- exported. Among Tucson's active-definition rows, 114,667 are open-ended and
-- 18,973 are date-ended, so the flag carries real information.
--
-- External ID grain / uniqueness contract: V_QUERY_CONSTITUENCY.ID is populated
-- only for manual/base and date-range-derived rows (it equals CONSTITUENCY.ID for
-- the 63,694 base rows) and is NULL for the system-derived rows. So we key on the
-- row's own ID when present (keeps prior external IDs stable / upsert-idempotent)
-- and otherwise synthesize a deterministic key from
-- (CONSTITUENTID, CONSTITUENCYDEFINITIONID) -- the natural grain of a constituency
-- assignment (CONSTITUENCYDEFINITIONID is never NULL); the 'SYS_' prefix cannot
-- collide with the GUID IDs.
--   That synthesized grain is coarser than the raw view grain, so if a future
-- tenant ever holds two ID-NULL view rows for the same
-- (CONSTITUENTID, CONSTITUENCYDEFINITIONID) -- e.g. a system role derived from two
-- separate activities -- they would map to the SAME external ID. A duplicate
-- Implementation_External_ID__c fails the Salesforce upsert batch outright, so we
-- collapse such rows deterministically (ROW_NUMBER, keep earliest DATEFROM) rather
-- than relying on the source happening to be unique. This is the AC-required
-- "do not multiply a role beyond the Altru UI grain" behaviour, guaranteed by
-- construction. Non-synthesized (ID-backed) rows are globally unique, so their
-- partitions are size 1 and this dedup is a no-op for them. (Tucson and Aspen both
-- had zero post-join collisions today; this only hardens the guarantee.)
WITH ConstituencyRows AS (
        SELECT
                COALESCE(
                        CAST(vq.ID AS VARCHAR(36)),
                        CONCAT(
                                'SYS_',
                                CAST(vq.CONSTITUENTID AS VARCHAR(36)),
                                '_',
                                CAST(vq.CONSTITUENCYDEFINITIONID AS VARCHAR(36))
                        )
                ) AS Implementation_External_ID__c,
                CASE
                        WHEN ct.ISCONSTITUENT = 1
                        AND ct.ISGROUP = 0
                        AND ct.ISORGANIZATION = 0 THEN ct.ID
                        ELSE NULL
                END AS Contact__c,
                CASE
                        WHEN ct.ISGROUP = 1
                        OR ct.ISORGANIZATION = 1 THEN ct.ID
                        ELSE ch.HOUSEHOLDID
                END AS Organization__c,
                vq.CONSTITUENCY AS Constituency__c,
                CASE
                        WHEN vq.DATETO IS NULL THEN 1
                        ELSE 0
                END AS Is_Active__c,
                vq.DATEFROM AS Date_From__c,
                vq.DATETO AS Date_To__c
        FROM
                V_QUERY_CONSTITUENCY vq
        JOIN CONSTITUENT ct ON
                vq.CONSTITUENTID = ct.ID
        LEFT JOIN CONSTITUENTHOUSEHOLD ch ON
                ch.ID = ct.ID
        WHERE
                vq.ISACTIVE = 1
),
RankedConstituencyRows AS (
        SELECT
                Implementation_External_ID__c,
                Contact__c,
                Organization__c,
                Constituency__c,
                Is_Active__c,
                Date_From__c,
                Date_To__c,
                ROW_NUMBER() OVER (
                        PARTITION BY Implementation_External_ID__c
                        ORDER BY Date_From__c ASC, Date_To__c ASC
                ) AS RowRank
        FROM
                ConstituencyRows
)
SELECT
        'CONSTITUENCY' AS QueryGroup,
        Implementation_External_ID__c,
        Contact__c,
        Organization__c,
        Constituency__c,
        Is_Active__c,
        Date_From__c,
        Date_To__c
FROM
        RankedConstituencyRows
WHERE
        RowRank = 1
