SET NOCOUNT ON;

PRINT '=== REV-10680447 anchor detail: membership line + all refunds linked ===';

DECLARE @ft_id UNIQUEIDENTIFIER = '00B8A1EE-DAFB-4801-AADF-4AD02B568140';

PRINT '-- Membership lines (Standard) on the Payment FT';
SELECT
    CAST(li.ID AS NVARCHAR(36))                  AS line_id,
    li.[TYPE]                                    AS line_type,
    CAST(li.TRANSACTIONAMOUNT AS NVARCHAR(20))   AS line_amount,
    CASE WHEN mt.ID IS NOT NULL THEN 'membership' ELSE 'other' END AS line_role
FROM FINANCIALTRANSACTIONLINEITEM li
LEFT JOIN MEMBERSHIPTRANSACTION mt ON mt.REVENUESPLITID = li.ID
WHERE li.FINANCIALTRANSACTIONID = @ft_id
ORDER BY li.[TYPE];

PRINT '-- Refund lines pointing at the membership lines (Branch A via SOURCELINEITEMID)';
SELECT
    CAST(refund_line.ID AS NVARCHAR(36))             AS refund_line_id,
    refund_line.[TYPE]                                AS refund_line_type,
    CAST(refund_line.TRANSACTIONAMOUNT AS NVARCHAR(20)) AS refund_amount,
    CAST(refund_ft.ID AS NVARCHAR(36))                AS refund_ft_id,
    refund_ft.[TYPE]                                  AS refund_ft_type,
    CONVERT(NVARCHAR(10), refund_ft.CALCULATEDDATE, 23) AS refund_date,
    CAST(orig_line.ID AS NVARCHAR(36))                AS original_line_id,
    CAST(orig_line.TRANSACTIONAMOUNT AS NVARCHAR(20)) AS original_amount
FROM FINANCIALTRANSACTIONLINEITEM refund_line
JOIN FINANCIALTRANSACTION refund_ft ON refund_ft.ID = refund_line.FINANCIALTRANSACTIONID AND refund_ft.[TYPE] = 'Refund'
JOIN FINANCIALTRANSACTIONLINEITEM orig_line ON orig_line.ID = refund_line.SOURCELINEITEMID
WHERE orig_line.FINANCIALTRANSACTIONID = @ft_id
  AND orig_line.[TYPE] = 'Standard';

PRINT '-- Cumulative gate verdict for the membership line(s) of REV-10680447';
SELECT
    CAST(mt.ID AS NVARCHAR(36))                      AS mt_id,
    CAST(orig_line.TRANSACTIONAMOUNT AS NVARCHAR(20)) AS original_amount,
    CAST(COALESCE(SUM(refund_line.TRANSACTIONAMOUNT), 0) AS NVARCHAR(20)) AS total_refund,
    CASE
        WHEN ABS(COALESCE(SUM(refund_line.TRANSACTIONAMOUNT), 0)) >= ABS(orig_line.TRANSACTIONAMOUNT)
            THEN 'Closed Lost (full or over-refund)'
        WHEN COALESCE(SUM(refund_line.TRANSACTIONAMOUNT), 0) = 0
            THEN 'Closed Won (no refund link)'
        ELSE 'Closed Won (partial refund -- the fix)'
    END AS new_gate_verdict
FROM MEMBERSHIPTRANSACTION mt
JOIN FINANCIALTRANSACTIONLINEITEM orig_line ON orig_line.ID = mt.REVENUESPLITID
LEFT JOIN FINANCIALTRANSACTIONLINEITEM refund_line
    ON refund_line.SOURCELINEITEMID = mt.REVENUESPLITID
   AND refund_line.[TYPE] = 'Standard'
LEFT JOIN FINANCIALTRANSACTION refund_ft
    ON refund_ft.ID = refund_line.FINANCIALTRANSACTIONID
   AND refund_ft.[TYPE] = 'Refund'
WHERE orig_line.FINANCIALTRANSACTIONID = @ft_id
  AND orig_line.[TYPE] = 'Standard'
GROUP BY mt.ID, orig_line.TRANSACTIONAMOUNT;
