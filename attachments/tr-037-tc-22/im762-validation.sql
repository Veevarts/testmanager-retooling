SET NOCOUNT ON;

/* ============================================================ */
/* IM-762 PR 111 — Partial refunds gated by completeness         */
/* PR diagnostic (Tucson):                                       */
/*   rmt A flips Lost->Won: 22                                   */
/*   rmt B flips Lost->Won: 14                                   */
/*   rso flips Lost->Won:   821                                  */
/*   Total Opportunities corrected: 857                          */
/*   Won->Lost regressions: 0                                    */
/*   MT count invariant: 98,487                                  */
/* Anchors (Tucson):                                             */
/*   REV-10680447  $65 / $10 partial -> Closed Won (was Lost)    */
/*   REV-10298505  $70 / $60 partial -> Closed Won (was Lost)    */
/*   REV-10612863  $65 / $46 partial -> Closed Won (was Lost)    */
/*   REV-10189020  $70 / $70 full    -> Closed Lost (unchanged)  */
/*   REV-10197952  $65 / $65 full    -> Closed Lost (unchanged)  */
/* ============================================================ */

PRINT '=== R1: rso_flips (SalesOrders moving Lost -> Won) ===';
/* Old logic: any refund link -> Closed Lost.                   */
/* New logic: only if ABS(SUM refund) >= ABS(MAX so_amount).    */
/* Flips = Old set minus New set.                               */

WITH SalesOrdersByPayment AS (
    SELECT
        sop.PAYMENTID,
        MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
),
CreditPaymentPerRefund AS (
    SELECT
        cp.CREDITID,
        MIN(cp.REVENUEID) AS OriginalPaymentTransactionId
    FROM CREDITPAYMENT cp
    GROUP BY cp.CREDITID
),
rso_base AS (
    SELECT
        COALESCE(original_so.ID, payment_so.ID, refund_so.ID) AS SalesOrderID,
        refund_ft.TRANSACTIONAMOUNT                           AS RefundAmount,
        COALESCE(original_so.AMOUNT, payment_so.AMOUNT, refund_so.AMOUNT)
                                                              AS SalesOrderAmount
    FROM FINANCIALTRANSACTION refund_ft
    INNER JOIN CreditPaymentPerRefund cp ON cp.CREDITID = refund_ft.ID
    LEFT JOIN SALESORDER original_so ON original_so.REVENUEID = cp.OriginalPaymentTransactionId
    LEFT JOIN SalesOrdersByPayment refund_sop ON refund_sop.PAYMENTID = cp.OriginalPaymentTransactionId
    LEFT JOIN SALESORDER payment_so ON payment_so.ID = refund_sop.SalesOrderID
    LEFT JOIN SALESORDER refund_so ON refund_so.REVENUEID = refund_ft.ID
    WHERE refund_ft.[TYPE] = 'Refund'
      AND COALESCE(original_so.ID, payment_so.ID, refund_so.ID) IS NOT NULL
),
rso_old AS (
    SELECT DISTINCT SalesOrderID FROM rso_base
),
rso_new AS (
    SELECT SalesOrderID
    FROM rso_base
    GROUP BY SalesOrderID
    HAVING ABS(SUM(RefundAmount)) >= ABS(MAX(ISNULL(SalesOrderAmount, 0)))
)
SELECT
    (SELECT COUNT(*) FROM rso_old)  AS rso_old_count,
    (SELECT COUNT(*) FROM rso_new)  AS rso_new_count,
    (SELECT COUNT(*) FROM rso_old) - (SELECT COUNT(*) FROM rso_new) AS rso_flips;

PRINT '=== R2: rmt A flips (RefundedMembershipTransactions Branch A) ===';

WITH rmta_old AS (
    SELECT DISTINCT mt.ID AS MembershipTransactionID
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM original_line
        ON original_line.ID = mt.REVENUESPLITID
       AND original_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.SOURCELINEITEMID = mt.REVENUESPLITID
       AND refund_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = refund_line.FINANCIALTRANSACTIONID
       AND refund_ft.[TYPE] = 'Refund'
),
rmta_new AS (
    SELECT mt.ID AS MembershipTransactionID
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM original_line
        ON original_line.ID = mt.REVENUESPLITID
       AND original_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.SOURCELINEITEMID = mt.REVENUESPLITID
       AND refund_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = refund_line.FINANCIALTRANSACTIONID
       AND refund_ft.[TYPE] = 'Refund'
    GROUP BY mt.ID, original_line.TRANSACTIONAMOUNT
    HAVING ABS(SUM(refund_line.TRANSACTIONAMOUNT)) >= ABS(MAX(original_line.TRANSACTIONAMOUNT))
)
SELECT
    (SELECT COUNT(*) FROM rmta_old) AS rmta_old_count,
    (SELECT COUNT(*) FROM rmta_new) AS rmta_new_count,
    (SELECT COUNT(*) FROM rmta_old) - (SELECT COUNT(*) FROM rmta_new) AS rmta_flips;

PRINT '=== R3: rmt B flips (RefundedMembershipTransactions Branch B - rank=1 only) ===';

WITH rm_ranked AS (
    SELECT
        mt.ID                          AS MembershipTransactionID,
        mt.REVENUESPLITID              AS RevenueSplitId,
        refund_line.TRANSACTIONAMOUNT  AS RefundAmount,
        ROW_NUMBER() OVER (
            PARTITION BY refund_ft.ID, cim.MEMBERSHIPID
            ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
        ) AS RefundMatchRank
    FROM FINANCIALTRANSACTION refund_ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.FINANCIALTRANSACTIONID = refund_ft.ID
       AND refund_line.[TYPE] = 'Standard'
    INNER JOIN CREDITITEMMEMBERSHIP cim
        ON cim.ID = refund_line.SOURCELINEITEMID
        OR cim.ID = refund_line.ID
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
       AND mt.TRANSACTIONDATE <= refund_ft.CALCULATEDDATE
    WHERE refund_ft.[TYPE] = 'Refund'
),
rmtb_old AS (
    SELECT DISTINCT MembershipTransactionID
    FROM rm_ranked
    WHERE RefundMatchRank = 1
),
rmtb_new AS (
    SELECT rm.MembershipTransactionID
    FROM rm_ranked rm
    LEFT JOIN FINANCIALTRANSACTIONLINEITEM original_line
        ON original_line.ID = rm.RevenueSplitId
       AND original_line.[TYPE] = 'Standard'
    WHERE rm.RefundMatchRank = 1
    GROUP BY rm.MembershipTransactionID
    HAVING ABS(SUM(rm.RefundAmount)) >= ABS(MAX(ISNULL(original_line.TRANSACTIONAMOUNT, 0)))
)
SELECT
    (SELECT COUNT(*) FROM rmtb_old) AS rmtb_old_count,
    (SELECT COUNT(*) FROM rmtb_new) AS rmtb_new_count,
    (SELECT COUNT(*) FROM rmtb_old) - (SELECT COUNT(*) FROM rmtb_new) AS rmtb_flips;

PRINT '=== R4: Anchor REV-10680447 detail (IM-762 ticket case) ===';

SELECT
    ft.CALCULATEDUSERDEFINEDID AS rev_id,
    CAST(ft.ID AS NVARCHAR(36)) AS ft_id,
    ft.[TYPE]                  AS ft_type,
    CAST(ft.TRANSACTIONAMOUNT AS NVARCHAR(20)) AS ft_amount,
    CONVERT(NVARCHAR(10), ft.CALCULATEDDATE, 23) AS ft_date
FROM FINANCIALTRANSACTION ft
WHERE ft.CALCULATEDUSERDEFINEDID = 'REV-10680447';

PRINT '=== R5: 5-anchor contract matrix (original + total refund + gate result) ===';

WITH anchor_fts AS (
    SELECT ft.ID, ft.CALCULATEDUSERDEFINEDID AS rev_id
    FROM FINANCIALTRANSACTION ft
    WHERE ft.CALCULATEDUSERDEFINEDID IN (
        'REV-10680447', 'REV-10298505', 'REV-10612863',
        'REV-10189020', 'REV-10197952'
    )
),
anchor_originals AS (
    SELECT
        af.rev_id,
        af.ID                                    AS ft_id,
        mt.ID                                    AS mt_id,
        mt.REVENUESPLITID                        AS revenue_split_id,
        original_line.TRANSACTIONAMOUNT          AS original_amount
    FROM anchor_fts af
    INNER JOIN FINANCIALTRANSACTIONLINEITEM original_line
        ON original_line.FINANCIALTRANSACTIONID = af.ID
       AND original_line.[TYPE] = 'Standard'
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.REVENUESPLITID = original_line.ID
),
anchor_refunds AS (
    SELECT
        ao.rev_id,
        ao.mt_id,
        ao.original_amount,
        COALESCE(SUM(refund_line.TRANSACTIONAMOUNT), 0) AS total_refund_amount
    FROM anchor_originals ao
    LEFT JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.SOURCELINEITEMID = ao.revenue_split_id
       AND refund_line.[TYPE] = 'Standard'
    LEFT JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = refund_line.FINANCIALTRANSACTIONID
       AND refund_ft.[TYPE] = 'Refund'
    GROUP BY ao.rev_id, ao.mt_id, ao.original_amount
)
SELECT
    rev_id,
    CAST(original_amount AS NVARCHAR(20))         AS original_amount,
    CAST(total_refund_amount AS NVARCHAR(20))     AS total_refund_amount,
    CASE
        WHEN ABS(total_refund_amount) >= ABS(ISNULL(original_amount, 0)) THEN 'Closed Lost (refund completo)'
        WHEN total_refund_amount = 0 THEN 'Closed Won (sin refund)'
        ELSE 'Closed Won (refund parcial; pre-fix era Closed Lost)'
    END AS new_gate_stagename
FROM anchor_refunds
ORDER BY rev_id;
