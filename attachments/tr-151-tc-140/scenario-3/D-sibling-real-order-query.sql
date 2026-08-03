DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom DATETIME2 = '1900-01-01';
DECLARE @dateFilterTo DATETIME2 = '2100-12-31';
DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

;WITH FilteredSalesOrders AS (
    SELECT
        so.ID,
        so.REVENUEID
    FROM SALESORDER so
    WHERE
        so.STATUSCODE NOT IN (0, 6, 7)
        AND (
            @useDateFrom = 0
            OR so.TRANSACTIONDATE >= @filterDateFrom
            OR (
                so.TRANSACTIONDATE IS NULL
                AND so.DATEADDED >= @filterDateFrom
            )
        )
        AND (
            @useDateTo = 0
            OR so.TRANSACTIONDATE < DATEADD(DAY, 1, @filterDateTo)
            OR (
                so.TRANSACTIONDATE IS NULL
                AND so.DATEADDED < DATEADD(DAY, 1, @filterDateTo)
            )
        )
),
MembershipFinancialTransactions AS (
    SELECT DISTINCT
        membership_transactions.FINANCIALTRANSACTIONID
    FROM (
        SELECT
            ftl.FINANCIALTRANSACTIONID
        FROM FINANCIALTRANSACTIONLINEITEM ftl
        INNER JOIN REVENUESPLIT_EXT direct_rse
            ON direct_rse.ID = ftl.ID
           AND direct_rse.APPLICATION IN ('Membership', 'Membership add-on')
        WHERE ftl.[TYPE] = 'Standard'

        UNION ALL

        SELECT
            ftl.FINANCIALTRANSACTIONID
        FROM FINANCIALTRANSACTIONLINEITEM ftl
        INNER JOIN REVENUESPLIT_EXT source_rse
            ON source_rse.ID = ftl.SOURCELINEITEMID
           AND source_rse.APPLICATION IN ('Membership', 'Membership add-on')
        WHERE ftl.[TYPE] = 'Standard'

        UNION ALL

        SELECT
            ftl.FINANCIALTRANSACTIONID
        FROM FINANCIALTRANSACTIONLINEITEM ftl
        INNER JOIN CREDITITEMMEMBERSHIP cim
            ON cim.ID = ftl.ID
        WHERE ftl.[TYPE] = 'Standard'

        UNION ALL

        SELECT
            ftl.FINANCIALTRANSACTIONID
        FROM FINANCIALTRANSACTIONLINEITEM ftl
        INNER JOIN CREDITITEMMEMBERSHIP cim
            ON cim.ID = ftl.SOURCELINEITEMID
        WHERE ftl.[TYPE] = 'Standard'
    ) membership_transactions
),
EligibleLines AS (
    SELECT
        dli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        CASE
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount
    FROM FINANCIALTRANSACTIONLINEITEM dli
    LEFT JOIN REVENUESPLIT_EXT rse
        ON rse.ID = dli.ID
    WHERE dli.[TYPE] IN ('Standard', 'Reversal')
      AND (
            (
                dli.[TYPE] = 'Reversal'
                AND EXISTS (
                    SELECT 1
                    FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                    LEFT JOIN REVENUESPLIT_EXT reversed_rse
                        ON reversed_rse.ID = reversed_dli.ID
                    WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                      AND NULLIF(reversed_rse.APPLICATION, '') IN ('Membership', 'Membership add-on')
                )
            )
            OR (
                dli.[TYPE] <> 'Reversal'
                AND NULLIF(rse.APPLICATION, '') IN ('Membership', 'Membership add-on')
            )
      )
),
TransactionAgg AS (
    SELECT
        el.FinancialTransactionID,
        SUM(el.NetAmount) AS Amount
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
),
MembershipSalesOrders AS (
    SELECT
        fso.ID AS SalesOrderID,
        CAST(NULL AS UNIQUEIDENTIFIER) AS FinancialTransactionID,
        3 AS ResolutionRank
    FROM FilteredSalesOrders fso
    INNER JOIN SALESORDERITEM soi
        ON soi.SALESORDERID = fso.ID
    INNER JOIN SALESORDERITEMMEMBERSHIP soim
        ON soim.ID = soi.ID

    UNION ALL

    SELECT
        fso.ID AS SalesOrderID,
        CAST(NULL AS UNIQUEIDENTIFIER) AS FinancialTransactionID,
        3 AS ResolutionRank
    FROM FilteredSalesOrders fso
    INNER JOIN SALESORDERITEM soi
        ON soi.SALESORDERID = fso.ID
    INNER JOIN SALESORDERITEMMEMBERSHIPADDON soima
        ON soima.ID = soi.ID

    UNION ALL

    SELECT
        fso.ID AS SalesOrderID,
        fso.REVENUEID AS FinancialTransactionID,
        1 AS ResolutionRank
    FROM FilteredSalesOrders fso
    INNER JOIN MembershipFinancialTransactions mft
        ON mft.FINANCIALTRANSACTIONID = fso.REVENUEID

    UNION ALL

    SELECT
        fso.ID AS SalesOrderID,
        sop.PAYMENTID AS FinancialTransactionID,
        2 AS ResolutionRank
    FROM FilteredSalesOrders fso
    INNER JOIN SALESORDERPAYMENT sop
        ON sop.SALESORDERID = fso.ID
    INNER JOIN MembershipFinancialTransactions mft
        ON mft.FINANCIALTRANSACTIONID = sop.PAYMENTID
),
ResolvedSalesOrders AS (
    SELECT
        SalesOrderID,
        FinancialTransactionID
    FROM (
        SELECT
            fso.ID AS SalesOrderID,
            COALESCE(mso.FinancialTransactionID, fso.REVENUEID) AS FinancialTransactionID,
            ROW_NUMBER() OVER (
                PARTITION BY fso.ID
                ORDER BY
                    mso.ResolutionRank,
                    mso.FinancialTransactionID
            ) AS SalesOrderResolutionRank
        FROM MembershipSalesOrders mso
        INNER JOIN FilteredSalesOrders fso
            ON fso.ID = mso.SalesOrderID
    ) ranked_sales_orders
    WHERE SalesOrderResolutionRank = 1
)
SELECT COUNT(*) AS sibling_rows,
  COUNT(DISTINCT CAST(so.ID AS NVARCHAR(100))) AS sibling_distinct_keys,
  SUM(CASE WHEN CAST(so.ID AS NVARCHAR(100)) LIKE 'membership-no-order-pos-%' THEN 1 ELSE 0 END) AS sibling_synthetic_prefixed
FROM
        ResolvedSalesOrders rso
LEFT JOIN TransactionAgg ta
    ON ta.FinancialTransactionID = rso.FinancialTransactionID
LEFT JOIN FINANCIALTRANSACTION ft
    ON
        ft.ID = rso.FinancialTransactionID
INNER JOIN SALESORDER so
    ON
        so.ID = rso.SalesOrderID
LEFT JOIN ADDRESS addr
    ON
        so.ADDRESSID = addr.ID
LEFT JOIN CONSTITUENTHOUSEHOLD
 chh
    ON
        so.CONSTITUENTID = chh.ID
LEFT JOIN CONSTITUENT c ON
        c.ID = so.CONSTITUENTID
