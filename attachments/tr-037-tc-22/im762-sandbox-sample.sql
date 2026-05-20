SET NOCOUNT ON;

/* ============================================================ */
/* IM-762 Scenario 4 — Sample curado para upsert funcional       */
/*   - 4 partial rso flips    (gate = Closed Won)                */
/*   - 1 complete rso         (gate = Closed Lost, control)      */
/*   - 2 partial rmta flips   (gate = Closed Won)                */
/*   - 1 complete rmta        (gate = Closed Lost, control)      */
/*   - 2 partial rmtb flips   (gate = Closed Won)                */
/*   - 1 complete rmtb        (gate = Closed Lost, control)      */
/* All as Opportunity rows con external_id = SO.ID o MT.ID       */
/* ============================================================ */

PRINT '=== rso partial sample (top 4 by refund magnitude) ===';

WITH SalesOrdersByPayment AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop
    GROUP BY sop.PAYMENTID
),
CreditPaymentPerRefund AS (
    SELECT cp.CREDITID, MIN(cp.REVENUEID) AS OriginalPaymentTransactionId
    FROM CREDITPAYMENT cp
    GROUP BY cp.CREDITID
),
rso_base AS (
    SELECT
        COALESCE(original_so.ID, payment_so.ID, refund_so.ID) AS SalesOrderID,
        refund_ft.TRANSACTIONAMOUNT                           AS RefundAmount,
        COALESCE(original_so.AMOUNT, payment_so.AMOUNT, refund_so.AMOUNT) AS SalesOrderAmount,
        COALESCE(original_so.DATEADDED, payment_so.DATEADDED, refund_so.DATEADDED) AS SODate
    FROM FINANCIALTRANSACTION refund_ft
    INNER JOIN CreditPaymentPerRefund cp ON cp.CREDITID = refund_ft.ID
    LEFT JOIN SALESORDER original_so ON original_so.REVENUEID = cp.OriginalPaymentTransactionId
    LEFT JOIN SalesOrdersByPayment refund_sop ON refund_sop.PAYMENTID = cp.OriginalPaymentTransactionId
    LEFT JOIN SALESORDER payment_so ON payment_so.ID = refund_sop.SalesOrderID
    LEFT JOIN SALESORDER refund_so ON refund_so.REVENUEID = refund_ft.ID
    WHERE refund_ft.[TYPE] = 'Refund'
      AND COALESCE(original_so.ID, payment_so.ID, refund_so.ID) IS NOT NULL
),
rso_agg AS (
    SELECT
        SalesOrderID,
        SUM(RefundAmount)               AS total_refund,
        MAX(ISNULL(SalesOrderAmount,0)) AS so_amount,
        MAX(SODate)                     AS so_date
    FROM rso_base
    GROUP BY SalesOrderID
)
SELECT TOP 4
    CAST(SalesOrderID AS NVARCHAR(36)) AS ext_id,
    'rso_partial' AS bucket,
    CAST(so_amount AS NVARCHAR(20))    AS original_amount,
    CAST(total_refund AS NVARCHAR(20)) AS total_refund,
    'Closed Won' AS new_stagename,
    CONVERT(NVARCHAR(10), so_date, 23) AS close_date
FROM rso_agg
WHERE ABS(total_refund) < ABS(so_amount)
  AND so_amount > 0
ORDER BY ABS(total_refund) DESC;

PRINT '=== rso complete sample (1 control) ===';

WITH SalesOrdersByPayment AS (
    SELECT sop.PAYMENTID, MIN(sop.SALESORDERID) AS SalesOrderID
    FROM SALESORDERPAYMENT sop GROUP BY sop.PAYMENTID
),
CreditPaymentPerRefund AS (
    SELECT cp.CREDITID, MIN(cp.REVENUEID) AS OriginalPaymentTransactionId
    FROM CREDITPAYMENT cp GROUP BY cp.CREDITID
),
rso_base AS (
    SELECT
        COALESCE(original_so.ID, payment_so.ID, refund_so.ID) AS SalesOrderID,
        refund_ft.TRANSACTIONAMOUNT                           AS RefundAmount,
        COALESCE(original_so.AMOUNT, payment_so.AMOUNT, refund_so.AMOUNT) AS SalesOrderAmount,
        COALESCE(original_so.DATEADDED, payment_so.DATEADDED, refund_so.DATEADDED) AS SODate
    FROM FINANCIALTRANSACTION refund_ft
    INNER JOIN CreditPaymentPerRefund cp ON cp.CREDITID = refund_ft.ID
    LEFT JOIN SALESORDER original_so ON original_so.REVENUEID = cp.OriginalPaymentTransactionId
    LEFT JOIN SalesOrdersByPayment refund_sop ON refund_sop.PAYMENTID = cp.OriginalPaymentTransactionId
    LEFT JOIN SALESORDER payment_so ON payment_so.ID = refund_sop.SalesOrderID
    LEFT JOIN SALESORDER refund_so ON refund_so.REVENUEID = refund_ft.ID
    WHERE refund_ft.[TYPE] = 'Refund'
      AND COALESCE(original_so.ID, payment_so.ID, refund_so.ID) IS NOT NULL
),
rso_agg AS (
    SELECT SalesOrderID, SUM(RefundAmount) AS total_refund,
           MAX(ISNULL(SalesOrderAmount,0)) AS so_amount,
           MAX(SODate) AS so_date
    FROM rso_base GROUP BY SalesOrderID
)
SELECT TOP 1
    CAST(SalesOrderID AS NVARCHAR(36)) AS ext_id,
    'rso_complete' AS bucket,
    CAST(so_amount AS NVARCHAR(20))    AS original_amount,
    CAST(total_refund AS NVARCHAR(20)) AS total_refund,
    'Closed Lost' AS new_stagename,
    CONVERT(NVARCHAR(10), so_date, 23) AS close_date
FROM rso_agg
WHERE ABS(total_refund) >= ABS(so_amount)
  AND so_amount > 0
ORDER BY so_amount DESC;

PRINT '=== rmta partial sample (top 2) ===';

WITH rmta_agg AS (
    SELECT
        mt.ID AS mt_id,
        MAX(original_line.TRANSACTIONAMOUNT)         AS original_amount,
        SUM(refund_line.TRANSACTIONAMOUNT)           AS total_refund,
        MAX(orig_ft.CALCULATEDDATE)                  AS orig_date
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM original_line
        ON original_line.ID = mt.REVENUESPLITID
       AND original_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION orig_ft
        ON orig_ft.ID = original_line.FINANCIALTRANSACTIONID
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.SOURCELINEITEMID = mt.REVENUESPLITID
       AND refund_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = refund_line.FINANCIALTRANSACTIONID
       AND refund_ft.[TYPE] = 'Refund'
    GROUP BY mt.ID
)
SELECT TOP 2
    CAST(mt_id AS NVARCHAR(36)) AS ext_id,
    'rmta_partial' AS bucket,
    CAST(original_amount AS NVARCHAR(20)) AS original_amount,
    CAST(total_refund AS NVARCHAR(20))    AS total_refund,
    'Closed Won' AS new_stagename,
    CONVERT(NVARCHAR(10), orig_date, 23) AS close_date
FROM rmta_agg
WHERE ABS(total_refund) < ABS(original_amount)
ORDER BY ABS(original_amount) DESC;

PRINT '=== rmta complete sample (1 control) ===';

WITH rmta_agg AS (
    SELECT
        mt.ID AS mt_id,
        MAX(original_line.TRANSACTIONAMOUNT) AS original_amount,
        SUM(refund_line.TRANSACTIONAMOUNT)   AS total_refund,
        MAX(orig_ft.CALCULATEDDATE)          AS orig_date
    FROM MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM original_line
        ON original_line.ID = mt.REVENUESPLITID
       AND original_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION orig_ft
        ON orig_ft.ID = original_line.FINANCIALTRANSACTIONID
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.SOURCELINEITEMID = mt.REVENUESPLITID
       AND refund_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION refund_ft
        ON refund_ft.ID = refund_line.FINANCIALTRANSACTIONID
       AND refund_ft.[TYPE] = 'Refund'
    GROUP BY mt.ID
)
SELECT TOP 1
    CAST(mt_id AS NVARCHAR(36)) AS ext_id,
    'rmta_complete' AS bucket,
    CAST(original_amount AS NVARCHAR(20)) AS original_amount,
    CAST(total_refund AS NVARCHAR(20))    AS total_refund,
    'Closed Lost' AS new_stagename,
    CONVERT(NVARCHAR(10), orig_date, 23) AS close_date
FROM rmta_agg
WHERE ABS(total_refund) >= ABS(original_amount)
ORDER BY ABS(original_amount) DESC;

PRINT '=== rmtb partial sample including REV-10680447 anchor ===';

WITH rm_ranked AS (
    SELECT
        mt.ID AS mt_id,
        mt.REVENUESPLITID AS rev_split_id,
        refund_line.TRANSACTIONAMOUNT AS RefundAmount,
        refund_ft.CALCULATEDDATE AS refund_date,
        mt.TRANSACTIONDATE AS mt_date,
        cim.MEMBERSHIPID AS membership_id,
        ROW_NUMBER() OVER (
            PARTITION BY refund_ft.ID, cim.MEMBERSHIPID
            ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
        ) AS rk
    FROM FINANCIALTRANSACTION refund_ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.FINANCIALTRANSACTIONID = refund_ft.ID
       AND refund_line.[TYPE] = 'Standard'
    INNER JOIN CREDITITEMMEMBERSHIP cim
        ON cim.ID = refund_line.SOURCELINEITEMID OR cim.ID = refund_line.ID
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
       AND mt.TRANSACTIONDATE <= refund_ft.CALCULATEDDATE
    WHERE refund_ft.[TYPE] = 'Refund'
),
rmtb_agg AS (
    SELECT
        rm.mt_id,
        SUM(rm.RefundAmount) AS total_refund,
        MAX(ISNULL(ol.TRANSACTIONAMOUNT,0)) AS original_amount,
        MAX(rm.mt_date) AS mt_date
    FROM rm_ranked rm
    LEFT JOIN FINANCIALTRANSACTIONLINEITEM ol ON ol.ID = rm.rev_split_id AND ol.[TYPE] = 'Standard'
    WHERE rm.rk = 1
    GROUP BY rm.mt_id
)
SELECT TOP 3
    CAST(mt_id AS NVARCHAR(36)) AS ext_id,
    'rmtb_partial' AS bucket,
    CAST(original_amount AS NVARCHAR(20)) AS original_amount,
    CAST(total_refund AS NVARCHAR(20))    AS total_refund,
    'Closed Won' AS new_stagename,
    CONVERT(NVARCHAR(10), mt_date, 23) AS close_date
FROM rmtb_agg
WHERE ABS(total_refund) < ABS(original_amount)
  AND original_amount > 0
ORDER BY ABS(original_amount) DESC;

PRINT '=== rmtb complete sample (1 control) ===';

WITH rm_ranked AS (
    SELECT
        mt.ID AS mt_id,
        mt.REVENUESPLITID AS rev_split_id,
        refund_line.TRANSACTIONAMOUNT AS RefundAmount,
        mt.TRANSACTIONDATE AS mt_date,
        cim.MEMBERSHIPID AS membership_id,
        ROW_NUMBER() OVER (
            PARTITION BY refund_ft.ID, cim.MEMBERSHIPID
            ORDER BY mt.TRANSACTIONDATE DESC, mt.ID DESC
        ) AS rk
    FROM FINANCIALTRANSACTION refund_ft
    INNER JOIN FINANCIALTRANSACTIONLINEITEM refund_line
        ON refund_line.FINANCIALTRANSACTIONID = refund_ft.ID
       AND refund_line.[TYPE] = 'Standard'
    INNER JOIN CREDITITEMMEMBERSHIP cim
        ON cim.ID = refund_line.SOURCELINEITEMID OR cim.ID = refund_line.ID
    INNER JOIN MEMBERSHIPTRANSACTION mt
        ON mt.MEMBERSHIPID = cim.MEMBERSHIPID
       AND mt.TRANSACTIONDATE <= refund_ft.CALCULATEDDATE
    WHERE refund_ft.[TYPE] = 'Refund'
),
rmtb_agg AS (
    SELECT
        rm.mt_id,
        SUM(rm.RefundAmount) AS total_refund,
        MAX(ISNULL(ol.TRANSACTIONAMOUNT,0)) AS original_amount,
        MAX(rm.mt_date) AS mt_date
    FROM rm_ranked rm
    LEFT JOIN FINANCIALTRANSACTIONLINEITEM ol ON ol.ID = rm.rev_split_id AND ol.[TYPE] = 'Standard'
    WHERE rm.rk = 1
    GROUP BY rm.mt_id
)
SELECT TOP 1
    CAST(mt_id AS NVARCHAR(36)) AS ext_id,
    'rmtb_complete' AS bucket,
    CAST(original_amount AS NVARCHAR(20)) AS original_amount,
    CAST(total_refund AS NVARCHAR(20))    AS total_refund,
    'Closed Lost' AS new_stagename,
    CONVERT(NVARCHAR(10), mt_date, 23) AS close_date
FROM rmtb_agg
WHERE ABS(total_refund) >= ABS(original_amount)
  AND original_amount > 0
ORDER BY ABS(original_amount) DESC;

PRINT '=== anchor REV-10680447 mt_id resolution ===';

SELECT TOP 1
    CAST(mt.ID AS NVARCHAR(36)) AS anchor_mt_id,
    CAST(li.TRANSACTIONAMOUNT AS NVARCHAR(20)) AS original_amount,
    CONVERT(NVARCHAR(10), mt.TRANSACTIONDATE, 23) AS mt_date
FROM FINANCIALTRANSACTION ft
JOIN FINANCIALTRANSACTIONLINEITEM li ON li.FINANCIALTRANSACTIONID = ft.ID AND li.[TYPE] = 'Standard'
JOIN CREDITITEMMEMBERSHIP cim ON cim.ID = li.ID
JOIN MEMBERSHIPTRANSACTION mt ON mt.MEMBERSHIPID = cim.MEMBERSHIPID AND mt.TRANSACTIONDATE <= ft.CALCULATEDDATE
WHERE ft.CALCULATEDUSERDEFINEDID = 'REV-10680447'
ORDER BY mt.TRANSACTIONDATE DESC;
