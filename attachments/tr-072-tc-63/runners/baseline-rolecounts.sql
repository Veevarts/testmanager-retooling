DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo BIT = 0;
DECLARE @dateFilterFrom DATE = NULL;
DECLARE @dateFilterTo DATE = NULL;
DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

WITH MembershipLineItems AS (
    SELECT
        mli.ID AS LineItemID,
        mli.FINANCIALTRANSACTIONID AS FinancialTransactionID,
        mli.TRANSACTIONAMOUNT AS MembershipAmount
    FROM
        FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse
        ON rse.APPLICATION = 'Membership'
       AND rse.ID = mli.ID
    WHERE
        mli.[TYPE] = 'Standard'
),
ResolvedMembershipFinancialTransactions AS (
    SELECT
        mt.ID AS MembershipTransactionID,
        ft.ID AS FinancialTransactionID,
        ft.CALCULATEDDATE AS FinancialTransactionDate,
        ROW_NUMBER() OVER (
            PARTITION BY mt.ID
            ORDER BY
                CASE
                    WHEN candidate_line.SOURCELINEITEMID = mt.REVENUESPLITID THEN 0
                    WHEN candidate_line.ID = mt.REVENUESPLITID THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN ft.[TYPE] = 'Refund' THEN 1
                    ELSE 0
                END,
                ft.CALCULATEDDATE DESC,
                candidate_line.DATEADDED DESC,
                ft.ID DESC
        ) AS ResolutionRank
    FROM
        MEMBERSHIPTRANSACTION mt
    INNER JOIN FINANCIALTRANSACTIONLINEITEM candidate_line
        ON (
            candidate_line.ID = mt.REVENUESPLITID
            OR candidate_line.SOURCELINEITEMID = mt.REVENUESPLITID
        )
        AND candidate_line.[TYPE] = 'Standard'
    INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = candidate_line.FINANCIALTRANSACTIONID
),
RecurringInstallments AS (
    SELECT
        RecurringInstallmentID,
        FinancialTransactionID,
        InstallmentAmount,
        InstallmentDate
    FROM (
        SELECT
            rgi.ID AS RecurringInstallmentID,
            rgi.REVENUEID AS FinancialTransactionID,
            rgi.TRANSACTIONAMOUNT AS InstallmentAmount,
            rgi.[DATE] AS InstallmentDate,
            ROW_NUMBER() OVER (
                PARTITION BY rgi.ID
                ORDER BY
                    CASE WHEN rgp.PAYMENTID IS NULL THEN 1 ELSE 0 END,
                    rgp.PAYMENTID
            ) AS InstallmentPaymentRank
        FROM
            RECURRINGGIFTINSTALLMENT rgi
        LEFT JOIN RECURRINGGIFTINSTALLMENTPAYMENT rgp
            ON rgi.ID = rgp.RECURRINGGIFTINSTALLMENTID
    ) recurring_installments
    WHERE
        InstallmentPaymentRank = 1
),
DonationLineItems AS (
    SELECT
        dli.SOURCELINEITEMID,
        dli.TRANSACTIONAMOUNT AS DonationAmount
    FROM
        FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN REVENUESPLIT_EXT drse
        ON drse.ID = dli.ID
        AND drse.APPLICATION = 'Donation'
    WHERE
        dli.[TYPE] = 'Standard'
),
DiscountLineItems AS (
    SELECT
        xli.SOURCELINEITEMID,
        SUM(xli.TRANSACTIONAMOUNT) AS DiscountAmount
    FROM
        FINANCIALTRANSACTIONLINEITEM xli
    WHERE
        xli.[TYPE] = 'Discount'
    GROUP BY
        xli.SOURCELINEITEMID
),
AddOnLineItems AS (
    SELECT
        soi.SALESORDERID,
        SUM(COALESCE(soi.TOTAL, 0)) AS AddOnTotal
    FROM
        SALESORDERITEM soi
    WHERE
        soi.[TYPE] = 'Membership add-on'
    GROUP BY
        soi.SALESORDERID
),
SalesOrdersByPayment AS (
    SELECT
        sop.PAYMENTID,
        MIN(sop.SALESORDERID) AS SalesOrderID
    FROM
        SALESORDERPAYMENT sop
    GROUP BY
        sop.PAYMENTID
)
SELECT Role, COUNT(*) AS RoleRows, SUM(CAST(IsPrimary AS INT)) AS PrimaryRows FROM (
SELECT
    pmember.CONSTITUENTID AS ContactId,
    COALESCE(rgi.RecurringInstallmentID, mt.ID) AS OpportunityId,
    pmember.ISPRIMARY AS IsPrimary,
    'Member' AS Role
FROM
    MEMBERSHIPTRANSACTION mt
INNER JOIN MEMBERSHIP m
    ON mt.MEMBERSHIPID = m.ID
INNER JOIN [MEMBER] pmember
    ON pmember.MEMBERSHIPID = m.ID
   AND pmember.ISDROPPED = 0
-- Only include individual contacts (orgs/groups are Accounts in Salesforce, not valid for Contact Roles)
INNER JOIN CONSTITUENT c
    ON c.ID = pmember.CONSTITUENTID
   AND c.ISCONSTITUENT = 1
   AND c.ISGROUP = 0
   AND c.ISORGANIZATION = 0
LEFT JOIN MembershipLineItems mli
    ON mli.LineItemID = mt.REVENUESPLITID
LEFT JOIN ResolvedMembershipFinancialTransactions rmft
    ON rmft.MembershipTransactionID = mt.ID
   AND rmft.ResolutionRank = 1
LEFT JOIN RecurringInstallments rgi
    ON rgi.FinancialTransactionID = rmft.FinancialTransactionID
LEFT JOIN DonationLineItems dli
    ON dli.SOURCELINEITEMID = mli.LineItemID
LEFT JOIN DiscountLineItems xli
    ON xli.SOURCELINEITEMID = mli.LineItemID
LEFT JOIN SALESORDERITEMMEMBERSHIP soim
    ON mt.ID = soim.MEMBERSHIPTRANSACTIONID
LEFT JOIN SALESORDERITEM soi
    ON soim.ID = soi.ID
LEFT JOIN SALESORDER so
    ON soi.SALESORDERID = so.ID
LEFT JOIN SALESORDER revenue_so
    ON revenue_so.REVENUEID = rmft.FinancialTransactionID
LEFT JOIN SalesOrdersByPayment sop
    ON sop.PAYMENTID = rmft.FinancialTransactionID
LEFT JOIN SALESORDER payment_so
    ON payment_so.ID = sop.SalesOrderID
LEFT JOIN AddOnLineItems aoi
    ON aoi.SALESORDERID = COALESCE(so.ID, revenue_so.ID, payment_so.ID)
-- Filters aligned with membership_transactions.sql to ensure every contact role
-- references an opportunity that actually gets created in Salesforce.
-- Date filter mirrors the outer-WHERE placement membership_transactions.sql
-- adopted in IM-618: date filter applied per-row using the same CloseDate
-- expression (`COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate,
-- mt.TRANSACTIONDATE)`) so a date-windowed run cannot leave contact roles
-- pointing at membership opportunities that were themselves filtered out.
WHERE
    ISNULL(mt.ACTION, '') <> 'Drop'
    AND (
        COALESCE(so.ID, revenue_so.ID, payment_so.ID) IS NULL
        OR COALESCE(so.STATUSCODE, revenue_so.STATUSCODE, payment_so.STATUSCODE) NOT IN (0, 6, 7)
    )
    -- IM-621: matches the relaxed inclusion gate in membership_transactions.sql
    -- so contact roles on $0 comp memberships still reference a valid opportunity.
    AND (
        COALESCE(so.ID, revenue_so.ID, payment_so.ID) IS NOT NULL
        OR mli.LineItemID IS NOT NULL
        OR rmft.FinancialTransactionID IS NOT NULL
        OR rgi.RecurringInstallmentID IS NOT NULL
        OR EXISTS (
            SELECT 1 FROM MEMBERSHIPADDON ma
            WHERE ma.MEMBERSHIPTRANSACTIONID = mt.ID
        )
    )
    AND (
        @useDateFrom = 0
        OR CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) >= @filterDateFrom
    )
    AND (
        @useDateTo = 0
        OR CAST(COALESCE(rgi.InstallmentDate, rmft.FinancialTransactionDate, mt.TRANSACTIONDATE) AS DATE) <= @filterDateTo
    )

) x GROUP BY Role;
