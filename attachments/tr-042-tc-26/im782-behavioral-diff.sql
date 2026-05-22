SET NOCOUNT ON;

/* ============================================================ */
/* IM-782 PR 115 — behavioral diff exhibition_capacity.sql       */
/*                                                                */
/* Cambio: remueve el predicate                                   */
/*   AND (@hasProgramIdFilter = 0 OR e.PROGRAMID = @programIdFilter) */
/*                                                                */
/* En la practica: el extractor SIEMPRE binds                     */
/*   @hasProgramIdFilter = 0 (porque programId nunca se setea)    */
/* Asi que el predicate evaluaba a (0=0 OR ...) = TRUE = no-op.   */
/*                                                                */
/* Verificacion: el row count + el output deben ser IDENTICOS     */
/* pre vs post. Re-emite los 2 queries (declarando los params)    */
/* y compara row counts.                                           */
/* ============================================================ */

PRINT '=== Pre-fix simulation (with dead predicate) ===';

DECLARE @hasDateFilterFrom_pre BIT = 0;
DECLARE @hasDateFilterTo_pre BIT = 0;
DECLARE @dateFilterFrom_pre DATETIME2 = '1900-01-01';
DECLARE @dateFilterTo_pre DATETIME2 = '2100-12-31';
DECLARE @hasProgramIdFilter_pre BIT = 0;  /* extractor always binds 0 */
DECLARE @programIdFilter_pre UNIQUEIDENTIFIER = NULL;

DECLARE @useDateFrom_pre BIT = IIF(@hasDateFilterFrom_pre = 1, 1, 0);
DECLARE @useDateTo_pre BIT = IIF(@hasDateFilterTo_pre = 1, 1, 0);
DECLARE @filterDateFrom_pre DATETIME2 = CAST(@dateFilterFrom_pre AS DATETIME2);
DECLARE @filterDateTo_pre DATETIME2 = CAST(@dateFilterTo_pre AS DATETIME2);

SELECT
    COUNT(*) AS prefix_row_count,
    SUM(CAST(CASE WHEN @hasProgramIdFilter_pre = 0 OR e.PROGRAMID = @programIdFilter_pre THEN 1 ELSE 0 END AS INT)) AS rows_passing_dead_predicate
FROM EVENT e
WHERE 1 = 1
    AND e.PROGRAMID IS NOT NULL
    AND (@useDateFrom_pre = 0 OR CAST(e.STARTDATETIMEWITHOFFSET AS DATETIME2) >= @filterDateFrom_pre)
    AND (@useDateTo_pre = 0 OR CAST(e.STARTDATETIMEWITHOFFSET AS DATETIME2) <= @filterDateTo_pre)
    AND (@hasProgramIdFilter_pre = 0 OR e.PROGRAMID = @programIdFilter_pre);

PRINT '=== Post-fix simulation (predicate removed) ===';

DECLARE @hasDateFilterFrom_post BIT = 0;
DECLARE @hasDateFilterTo_post BIT = 0;
DECLARE @dateFilterFrom_post DATETIME2 = '1900-01-01';
DECLARE @dateFilterTo_post DATETIME2 = '2100-12-31';

DECLARE @useDateFrom_post BIT = IIF(@hasDateFilterFrom_post = 1, 1, 0);
DECLARE @useDateTo_post BIT = IIF(@hasDateFilterTo_post = 1, 1, 0);
DECLARE @filterDateFrom_post DATETIME2 = CAST(@dateFilterFrom_post AS DATETIME2);
DECLARE @filterDateTo_post DATETIME2 = CAST(@dateFilterTo_post AS DATETIME2);

SELECT COUNT(*) AS postfix_row_count
FROM EVENT e
WHERE 1 = 1
    AND e.PROGRAMID IS NOT NULL
    AND (@useDateFrom_post = 0 OR CAST(e.STARTDATETIMEWITHOFFSET AS DATETIME2) >= @filterDateFrom_post)
    AND (@useDateTo_post = 0 OR CAST(e.STARTDATETIMEWITHOFFSET AS DATETIME2) <= @filterDateTo_post);

PRINT '=== Sample of 5 rows post-fix to confirm output schema unchanged ===';

SELECT TOP 5
    CAST(e.ID AS NVARCHAR(36))                                  AS Implementation_External_ID__c,
    e.LOOKUPID                                                   AS Lookup_ID__c,
    SWITCHOFFSET(e.STARTDATETIMEWITHOFFSET, '+00:00')            AS Auctifera__Date_Time__c,
    CAST(e.EVENTLOCATIONID AS NVARCHAR(36))                      AS Auctifera__Display_Storage_Location__c,
    e.NAME                                                       AS Auctifera__Session_Name__c,
    e.CAPACITY                                                   AS Auctifera__Target_Capacity__c,
    CAST(e.PROGRAMID AS NVARCHAR(36))                            AS PROGRAMID
FROM EVENT e
WHERE e.PROGRAMID IS NOT NULL
ORDER BY e.STARTDATETIMEWITHOFFSET DESC;
