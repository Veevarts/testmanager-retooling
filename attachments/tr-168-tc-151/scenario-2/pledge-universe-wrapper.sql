-- TC-151 / IM-1200 — pledge POS Purchase universe, PRE gate vs POST gate on the SAME snapshot.
-- Mirrors: donation_pledges.sql emission (ft.[TYPE] = 'Pledge', no date filter, unconditional
-- COALESCE(so.ID, ft.ID) reference) vs sales_order_only_pledge.sql minting gate PRE
-- (INNER JOIN agg HAVING SUM <> 0, base commit 5a6122d) and POST (unconditional, PR #170).
-- Aggregate-only output: counts and sums, no row-level data.
WITH QaPledgeAgg AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FtId,
        SUM(CASE WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT ELSE dli.TRANSACTIONAMOUNT END) AS Amount,
        SUM(CASE WHEN dli.[TYPE] = 'Reversal' THEN 1 ELSE 0 END) AS ReversalLines
    FROM FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN FINANCIALTRANSACTION ft ON ft.ID = dli.FINANCIALTRANSACTIONID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
      AND ft.TYPECODE = 1
    GROUP BY dli.FINANCIALTRANSACTIONID
),
QaPledgeOpps AS (
    SELECT ft.ID,
        CASE WHEN EXISTS (SELECT 1 FROM SALESORDER so WHERE so.REVENUEID = ft.ID) THEN 1 ELSE 0 END AS OrderBacked
    FROM FINANCIALTRANSACTION ft
    WHERE ft.[TYPE] = 'Pledge'
),
QaMintedPre AS (
    SELECT ft.ID
    FROM FINANCIALTRANSACTION ft
    INNER JOIN QaPledgeAgg ta ON ta.FtId = ft.ID AND ta.Amount <> 0
    WHERE ft.TYPECODE = 1
      AND NOT EXISTS (SELECT 1 FROM SALESORDER so WHERE so.REVENUEID = ft.ID)
),
QaMintedPost AS (
    SELECT ft.ID
    FROM FINANCIALTRANSACTION ft
    WHERE ft.TYPECODE = 1
      AND NOT EXISTS (SELECT 1 FROM SALESORDER so WHERE so.REVENUEID = ft.ID)
)
SELECT
    (SELECT COUNT(*) FROM QaPledgeOpps) AS pledge_opportunities,
    (SELECT COUNT(*) FROM QaPledgeOpps WHERE OrderBacked = 1) AS order_backed_pledges,
    (SELECT COUNT(*) FROM QaPledgeOpps WHERE OrderBacked = 0) AS orderless_pledges,
    (SELECT COUNT(*) FROM QaMintedPre) AS pre_minted_orderless,
    (SELECT COUNT(*) FROM QaPledgeOpps p
        WHERE p.OrderBacked = 0
          AND NOT EXISTS (SELECT 1 FROM QaMintedPre m WHERE m.ID = p.ID)) AS pre_dangling,
    (SELECT COUNT(*) FROM QaMintedPost) AS post_minted_orderless,
    (SELECT COUNT(*) FROM QaPledgeOpps p
        WHERE p.OrderBacked = 0
          AND NOT EXISTS (SELECT 1 FROM QaMintedPost m WHERE m.ID = p.ID)) AS post_dangling,
    (SELECT COUNT(*) FROM QaPledgeOpps p
        INNER JOIN QaPledgeAgg ta ON ta.FtId = p.ID
        WHERE p.OrderBacked = 0 AND ta.Amount = 0 AND ta.ReversalLines = 0
          AND NOT EXISTS (SELECT 1 FROM QaMintedPre m WHERE m.ID = p.ID)) AS pre_dangling_zero_dollar_no_reversal,
    (SELECT COUNT(*) FROM QaPledgeOpps p
        INNER JOIN QaPledgeAgg ta ON ta.FtId = p.ID
        WHERE p.OrderBacked = 0 AND ta.Amount = 0 AND ta.ReversalLines > 0
          AND NOT EXISTS (SELECT 1 FROM QaMintedPre m WHERE m.ID = p.ID)) AS pre_dangling_fully_reversed,
    (SELECT COUNT(*) FROM QaPledgeOpps p
        WHERE p.OrderBacked = 0
          AND NOT EXISTS (SELECT 1 FROM QaPledgeAgg ta WHERE ta.FtId = p.ID)
          AND NOT EXISTS (SELECT 1 FROM QaMintedPre m WHERE m.ID = p.ID)) AS pre_dangling_no_lines_at_all,
    (SELECT COUNT(*) FROM QaMintedPre
        WHERE ID IN ('aef807ba-59fc-4594-9e63-babe9f8f5083', 'e72b9b13-55b8-46f2-b184-6db67c60f111')) AS ticket_ids_minted_pre,
    (SELECT COUNT(*) FROM QaMintedPost
        WHERE ID IN ('aef807ba-59fc-4594-9e63-babe9f8f5083', 'e72b9b13-55b8-46f2-b184-6db67c60f111')) AS ticket_ids_minted_post,
    (SELECT COUNT(*) FROM QaPledgeOpps
        WHERE ID IN ('aef807ba-59fc-4594-9e63-babe9f8f5083', 'e72b9b13-55b8-46f2-b184-6db67c60f111')) AS ticket_ids_are_pledge_opps,
    (SELECT SUM(CASE WHEN COALESCE(ta.Amount, 0) <> 0 THEN 1 ELSE 0 END)
        FROM QaMintedPost m
        LEFT JOIN QaPledgeAgg ta ON ta.FtId = m.ID
        WHERE NOT EXISTS (SELECT 1 FROM QaMintedPre p2 WHERE p2.ID = m.ID)) AS new_rows_with_nonzero_amount,
    (SELECT SUM(COALESCE(ta.Amount, 0))
        FROM QaMintedPre m
        LEFT JOIN QaPledgeAgg ta ON ta.FtId = m.ID) AS pre_total_amount,
    (SELECT SUM(COALESCE(ta.Amount, 0))
        FROM QaMintedPost m
        LEFT JOIN QaPledgeAgg ta ON ta.FtId = m.ID) AS post_total_amount,
    (SELECT COUNT(*) - COUNT(DISTINCT ID) FROM QaMintedPost) AS post_duplicate_ids
