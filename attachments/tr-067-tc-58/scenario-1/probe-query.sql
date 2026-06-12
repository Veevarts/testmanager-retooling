-- IM-904 probe: validate posted date alignment for Peter Fletcher recurring rev-10282478
-- rgi.[DATE] is the actual column (aliased as InstallmentDate in the CTE)
-- Root recurring is matched by ft.CALCULATEDUSERDEFINEDID = 'rev-10282478'

SELECT TOP 50
    ft.CALCULATEDUSERDEFINEDID AS RecurringMappedID,
    rgi.ID AS RecurringInstallmentID,
    CAST(ft.DATE AS DATE) AS PreFix_PostedDate,
    CAST(COALESCE(rgi.[DATE], ft.DATE) AS DATE) AS PostFix_PostedDate,
    rgi.TRANSACTIONAMOUNT AS InstallmentAmount,
    YEAR(rgi.[DATE]) AS InstallmentYear
FROM FINANCIALTRANSACTION ft
LEFT JOIN RECURRINGGIFTINSTALLMENT rgi
    ON rgi.REVENUEID = ft.ID
WHERE ft.CALCULATEDUSERDEFINEDID = 'rev-10282478'
ORDER BY rgi.[DATE];
