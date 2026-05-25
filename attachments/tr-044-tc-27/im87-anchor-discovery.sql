SET NOCOUNT ON;

/* ============================================================ */
/* IM-87 — Anchor FT discovery for functional scenario          */
/* Goal: find a donation FT that:                                */
/*  - post-fix query emits a transaction-agg row                 */
/*  - has revenue-backed SO (so we can demo COALESCE)            */
/*  - ideally has multiple line items (line-grain vs FT-grain)   */
/*  - ideally has at least one Reversal line                     */
/* ============================================================ */

PRINT '=== R1: candidate FTs with multi-line donations + revenue SO + at least 1 Reversal line ===';
WITH MembershipLineItems AS (
    SELECT mli.ID AS MembershipLineItemID
    FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership' AND mli.[TYPE] = 'Standard'
),
EligibleLines AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        dli.ID AS LineItemID,
        dli.[TYPE] AS LineType,
        CASE WHEN dli.[TYPE]='Reversal' THEN -1*dli.TRANSACTIONAMOUNT ELSE dli.TRANSACTIONAMOUNT END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1,2,20)
      AND NOT EXISTS (
            SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM src
            INNER JOIN FINANCIALTRANSACTION ft_pledge ON ft_pledge.ID = src.FINANCIALTRANSACTIONID AND ft_pledge.TYPECODE = 1
            WHERE dli.SOURCELINEITEMID = src.ID
      )
      AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems m
            WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID)
      )
      AND (
            (dli.[TYPE]='Reversal' AND EXISTS (
                SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                LEFT JOIN REVENUESPLIT_EXT reversed_rse ON reversed_rse.ID = reversed_dli.ID
                WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                  AND NULLIF(reversed_rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift')
            ))
            OR (dli.[TYPE]<>'Reversal' AND NULLIF(rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift'))
      )
      AND (NULLIF(rse.[TYPE],'') IS NULL OR NULLIF(rse.[TYPE],'') NOT IN ('Membership'))
),
TransactionAgg AS (
    SELECT el.FinancialTransactionID,
           COUNT(*) AS LineCount,
           SUM(CASE WHEN el.LineType='Reversal' THEN 1 ELSE 0 END) AS ReversalLineCount,
           SUM(el.NetAmount) AS Amount
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
    HAVING SUM(el.NetAmount) <> 0
)
SELECT TOP 5
    CAST(ta.FinancialTransactionID AS NVARCHAR(36)) AS ft_id,
    ta.LineCount,
    ta.ReversalLineCount,
    CAST(ta.Amount AS NVARCHAR(20)) AS net_amount,
    CAST(so.ID AS NVARCHAR(36)) AS revenue_so_id,
    so.LOOKUPID AS so_lookup
FROM TransactionAgg ta
INNER JOIN SALESORDER so ON so.REVENUEID = ta.FinancialTransactionID
WHERE ta.LineCount > 1 AND ta.ReversalLineCount > 0
ORDER BY ta.LineCount DESC, ta.Amount DESC;

PRINT '=== R2: simpler candidate — multi-line, no reversal, revenue-backed (grain collapse only) ===';
WITH MembershipLineItems2 AS (
    SELECT mli.ID AS MembershipLineItemID
    FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership' AND mli.[TYPE] = 'Standard'
),
EligibleLines2 AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        CASE WHEN dli.[TYPE]='Reversal' THEN -1*dli.TRANSACTIONAMOUNT ELSE dli.TRANSACTIONAMOUNT END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1,2,20)
      AND NOT EXISTS (
            SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM src
            INNER JOIN FINANCIALTRANSACTION ft_pledge ON ft_pledge.ID = src.FINANCIALTRANSACTIONID AND ft_pledge.TYPECODE = 1
            WHERE dli.SOURCELINEITEMID = src.ID
      )
      AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems2 m
            WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID)
      )
      AND (
            (dli.[TYPE]='Reversal' AND EXISTS (
                SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                LEFT JOIN REVENUESPLIT_EXT reversed_rse ON reversed_rse.ID = reversed_dli.ID
                WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                  AND NULLIF(reversed_rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift')
            ))
            OR (dli.[TYPE]<>'Reversal' AND NULLIF(rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift'))
      )
      AND (NULLIF(rse.[TYPE],'') IS NULL OR NULLIF(rse.[TYPE],'') NOT IN ('Membership'))
),
TransactionAgg2 AS (
    SELECT el.FinancialTransactionID, COUNT(*) AS LineCount, SUM(el.NetAmount) AS Amount
    FROM EligibleLines2 el
    GROUP BY el.FinancialTransactionID
    HAVING SUM(el.NetAmount) <> 0
)
SELECT TOP 5
    CAST(ta.FinancialTransactionID AS NVARCHAR(36)) AS ft_id,
    ta.LineCount,
    CAST(ta.Amount AS NVARCHAR(20)) AS net_amount,
    CAST(so.ID AS NVARCHAR(36)) AS revenue_so_id,
    so.LOOKUPID AS so_lookup
FROM TransactionAgg2 ta
INNER JOIN SALESORDER so ON so.REVENUEID = ta.FinancialTransactionID
WHERE ta.LineCount BETWEEN 2 AND 4
ORDER BY ta.Amount DESC;

PRINT '=== R3: count of FTs with reversal lines + revenue SO (universe size for reversal-aware path) ===';
WITH MembershipLineItems3 AS (
    SELECT mli.ID AS MembershipLineItemID
    FROM FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse ON rse.ID = mli.ID
    WHERE rse.APPLICATION = 'Membership' AND mli.[TYPE] = 'Standard'
),
EligibleLines3 AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        dli.[TYPE] AS LineType
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dli.FINANCIALTRANSACTIONID
    LEFT JOIN REVENUESPLIT_EXT rse ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard','Reversal')
      AND ft.TYPECODE NOT IN (1,2,20)
      AND NOT EXISTS (
            SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM src
            INNER JOIN FINANCIALTRANSACTION ft_pledge ON ft_pledge.ID = src.FINANCIALTRANSACTIONID AND ft_pledge.TYPECODE = 1
            WHERE dli.SOURCELINEITEMID = src.ID
      )
      AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems3 m
            WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID)
      )
      AND (
            (dli.[TYPE]='Reversal' AND EXISTS (
                SELECT 1 FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                LEFT JOIN REVENUESPLIT_EXT reversed_rse ON reversed_rse.ID = reversed_dli.ID
                WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                  AND NULLIF(reversed_rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift')
            ))
            OR (dli.[TYPE]<>'Reversal' AND NULLIF(rse.APPLICATION,'') IN ('Donation','Recurring gift','Planned gift','Matching gift'))
      )
      AND (NULLIF(rse.[TYPE],'') IS NULL OR NULLIF(rse.[TYPE],'') NOT IN ('Membership'))
)
SELECT
    COUNT(DISTINCT el.FinancialTransactionID) AS fts_with_at_least_one_reversal
FROM EligibleLines3 el
WHERE el.LineType = 'Reversal';
