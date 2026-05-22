DECLARE @useDateFrom BIT = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo BIT = IIF(@hasDateFilterTo = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo DATE = CAST(@dateFilterTo AS DATE);

WITH 
MembershipLineItems AS (
    SELECT
        mli.ID AS MembershipLineItemID
    FROM
        FINANCIALTRANSACTIONLINEITEM mli
    INNER JOIN REVENUESPLIT_EXT rse
            ON rse.ID = mli.ID
    WHERE
            rse.APPLICATION = 'Membership'
        AND mli.[TYPE] = 'Standard'
),
EligibleLines AS (
    SELECT
        ft.ID AS FinancialTransactionID,
        CASE
            WHEN dli.[TYPE] = 'Reversal' THEN -1 * dli.TRANSACTIONAMOUNT
            ELSE dli.TRANSACTIONAMOUNT
        END AS NetAmount
    FROM
        FINANCIALTRANSACTIONLINEITEM dli
    LEFT JOIN REVENUESPLIT_EXT rse_line
        ON rse_line.ID = dli.ID
    JOIN FINANCIALTRANSACTION ft
        ON ft.ID = dli.FINANCIALTRANSACTIONID
    WHERE
        dli.[TYPE] IN ('Standard', 'Reversal')
        AND ft.TYPECODE NOT IN (1, 2, 20) -- Exclude Pledge, Recurring gift, Write off
        AND NOT EXISTS (
            SELECT 1
            FROM FINANCIALTRANSACTIONLINEITEM src
            JOIN FINANCIALTRANSACTION ft_pledge
                ON ft_pledge.ID = src.FINANCIALTRANSACTIONID
               AND ft_pledge.TYPECODE = 1
            WHERE dli.SOURCELINEITEMID = src.ID
        )
        AND NOT EXISTS (
            SELECT 1 FROM MembershipLineItems m
            WHERE m.MembershipLineItemID IN (dli.SOURCELINEITEMID, dli.REVERSEDLINEITEMID)
        )
        AND (
            (
                dli.[TYPE] = 'Reversal'
                AND EXISTS (
                    SELECT 1
                    FROM FINANCIALTRANSACTIONLINEITEM reversed_dli
                    LEFT JOIN REVENUESPLIT_EXT reversed_rse
                      ON reversed_rse.ID = reversed_dli.ID
                    WHERE reversed_dli.ID = dli.REVERSEDLINEITEMID
                      AND NULLIF(reversed_rse.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
                )
            )
            OR (
                dli.[TYPE] <> 'Reversal'
                AND NULLIF(rse_line.APPLICATION, '') IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
            )
        )
        AND (
            NULLIF(rse_line.[TYPE], '') IS NULL
            OR NULLIF(rse_line.[TYPE], '') NOT IN ('Membership')
        )
),
TransactionAgg AS (
    SELECT
        el.FinancialTransactionID,
        SUM(el.NetAmount) AS Amount
    FROM EligibleLines el
    GROUP BY el.FinancialTransactionID
),
DonationLineItems AS (
    SELECT
        ft.ID AS FinancialTransactionID,
        ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
        dli.ID AS LineItemID,
        dli.TRANSACTIONAMOUNT AS DonationAmount,
        rse.APPLICATION  AS Application,
        rse.[TYPE] AS Type,
        dli.SOURCELINEITEMID
    FROM
        FINANCIALTRANSACTIONLINEITEM dli
    INNER JOIN REVENUESPLIT_EXT rse
        ON rse.ID = dli.ID
        AND rse.APPLICATION IN ('Donation', 'Recurring gift', 'Planned gift', 'Matching gift')
        AND rse.[TYPE] NOT IN ('Membership')
    INNER JOIN FINANCIALTRANSACTION ft
        ON ft.ID = dli.FINANCIALTRANSACTIONID
    WHERE
        dli.[TYPE] = 'Standard'
        AND ft.[TYPE] <> 'Pledge'
        AND NOT EXISTS (
		    SELECT 1
		    FROM MembershipLineItems m
		    WHERE m.MembershipLineItemID = dli.SOURCELINEITEMID
		)
)
SELECT
    dli.LineItemID AS vnfp__Implementation_External_ID__c,
    so.LOOKUPID AS LookUp_ID_Legacy,
    ft.CALCULATEDUSERDEFINEDID AS Revenue_ID_legacy__c,
    CAST(rse.DESIGNATIONID AS VARCHAR(36)) AS Auctifera__Specific_Fund__c,
    d.NAME AS Auctifera__Specific_Fund_Name__c,
    'Posted' AS Auctifera__Accounting_Status__c,
    'Succeeded' AS Auctifera__Status__c,
    dli.DonationAmount AS Auctifera__Donated_Amount__c,
    CAST(ft.CALCULATEDDATE AS DATE) AS Auctifera__Posted_Date__c,
    'Acknowledged' AS vnfp__Acknowledgment_Status__c,
    CAST(ft.ID AS VARCHAR(36)) AS vnfp__Opportunity__c,
    so.ID AS vnfp__Opportunity_POS_Purchase__c
FROM
    DonationLineItems dli
INNER JOIN REVENUESPLIT_EXT rse
    ON rse.ID = dli.LineItemID
INNER JOIN FINANCIALTRANSACTION ft
    ON ft.ID = dli.FinancialTransactionID
INNER JOIN TransactionAgg ta
    ON ta.FinancialTransactionID = ft.ID
   AND ta.Amount <> 0 -- keep in sync with donation opportunities (exclude fully reversed)
LEFT JOIN SALESORDER so
    ON so.REVENUEID = ft.ID
LEFT JOIN DESIGNATION d
    ON rse.DESIGNATIONID = d.ID
WHERE
    (@useDateFrom = 0 OR CAST(ft.CALCULATEDDATE AS DATE) >= @filterDateFrom)
    AND (@useDateTo = 0 OR CAST(ft.CALCULATEDDATE AS DATE) <= @filterDateTo)
ORDER BY
    ft.CALCULATEDUSERDEFINEDID;
