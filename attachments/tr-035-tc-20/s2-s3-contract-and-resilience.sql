SET NOCOUNT ON;

/* ============================================================ */
/* IM-696 TC-20 Scenarios 2 & 3 — full attributes.sql wrapped    */
/* Captures the dynamic output into #out and aggregates for      */
/* per-row contract + routing + grain + typed slot integrity.    */
/* ============================================================ */

DECLARE @hasDateFilterFrom BIT = 0;
DECLARE @hasDateFilterTo   BIT = 0;
DECLARE @dateFilterFrom    DATE = NULL;
DECLARE @dateFilterTo      DATE = NULL;

IF OBJECT_ID('tempdb..#out') IS NOT NULL DROP TABLE #out;
CREATE TABLE #out (
    Implementation_External_ID__c UNIQUEIDENTIFIER,
    Contact__c                    UNIQUEIDENTIFIER,
    Household_Organization__c     UNIQUEIDENTIFIER,
    Attribute_Name__c             NVARCHAR(100),
    Attribute_Group__c            NVARCHAR(100),
    Data_Type__c                  NVARCHAR(20),
    Value_Text__c                 NVARCHAR(MAX),
    Value_Boolean__c              BIT,
    Value_Date__c                 DATE,
    Value_Number__c               DECIMAL(18,4),
    Comment__c                    NVARCHAR(MAX),
    Start_Date__c                 DATE,
    End_Date__c                   DATE,
    Source_Category_ID__c         UNIQUEIDENTIFIER,
    Source_Code_Table__c          NVARCHAR(128)
);


DECLARE @useDateFrom    BIT  = IIF(@hasDateFilterFrom = 1, 1, 0);
DECLARE @useDateTo      BIT  = IIF(@hasDateFilterTo   = 1, 1, 0);
DECLARE @filterDateFrom DATE = CAST(@dateFilterFrom AS DATE);
DECLARE @filterDateTo   DATE = CAST(@dateFilterTo   AS DATE);

DECLARE @branches NVARCHAR(MAX) = N'';

DECLARE @cat_id      UNIQUEIDENTIFIER;
DECLARE @cat_name    NVARCHAR(100);
DECLARE @cat_group   NVARCHAR(100);
DECLARE @cat_dtcode  TINYINT;
DECLARE @phys_table  SYSNAME;
DECLARE @phys_raw    SYSNAME;
DECLARE @code_table  SYSNAME;
DECLARE @code_raw    SYSNAME;

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
SELECT
        ac.ID,
        ac.NAME,
        agc.DESCRIPTION,
        ac.DATATYPECODE,
        QUOTENAME(tc.TABLENAME),
        tc.TABLENAME,
        QUOTENAME(ct.DBTABLENAME),
        ct.DBTABLENAME
FROM
        ATTRIBUTECATEGORY ac
JOIN TABLECATALOG tc
        ON tc.ID = ac.TABLECATALOGID
JOIN INFORMATION_SCHEMA.TABLES it
        ON it.TABLE_NAME = tc.TABLENAME
JOIN INFORMATION_SCHEMA.COLUMNS ic
        ON ic.TABLE_NAME = tc.TABLENAME AND ic.COLUMN_NAME = 'CONSTITUENTID'
LEFT JOIN ATTRIBUTEGROUPCODE agc
        ON agc.ID = ac.ATTRIBUTEGROUPCODEID
LEFT JOIN CODETABLECATALOG ct
        ON ct.ID = ac.CODETABLECATALOGID
WHERE
        ac.FLAGGEDFORDELETE = 0
    AND ac.FLAGGEDFOREXTENSIONREMOVAL = 0;

OPEN cur;
FETCH NEXT FROM cur
INTO @cat_id, @cat_name, @cat_group, @cat_dtcode,
     @phys_table, @phys_raw, @code_table, @code_raw;

WHILE @@FETCH_STATUS = 0
BEGIN
        DECLARE @value_text   NVARCHAR(MAX);
        DECLARE @value_bool   NVARCHAR(MAX);
        DECLARE @value_date   NVARCHAR(MAX);
        DECLARE @value_number NVARCHAR(MAX);
        DECLARE @value_join   NVARCHAR(MAX);
        DECLARE @data_type    NVARCHAR(20);
        DECLARE @code_column  SYSNAME;

        DECLARE @has_value_text    BIT;
        DECLARE @has_value_numeric BIT;
        DECLARE @has_value_date    BIT;
        DECLARE @has_boolean       BIT;
        DECLARE @has_codeid        BIT;

        SET @has_value_text    = 0;
        SET @has_value_numeric = 0;
        SET @has_value_date    = 0;
        SET @has_boolean       = 0;
        SET @has_codeid        = 0;
        SET @code_column       = NULL;

        SELECT
                @has_value_text = MAX(CASE
                        WHEN c.COLUMN_NAME = 'VALUE'
                         AND c.DATA_TYPE IN ('nvarchar','varchar','nchar','char','text','ntext')
                        THEN 1 ELSE 0 END),
                @has_value_numeric = MAX(CASE
                        WHEN c.COLUMN_NAME = 'VALUE'
                         AND c.DATA_TYPE IN ('money','decimal','numeric','int','bigint','smallint','tinyint','float','real')
                        THEN 1 ELSE 0 END),
                @has_value_date = MAX(CASE
                        WHEN c.COLUMN_NAME = 'VALUE'
                         AND c.DATA_TYPE IN ('datetime','datetime2','smalldatetime','date')
                        THEN 1 ELSE 0 END),
                @has_boolean = MAX(CASE
                        WHEN c.COLUMN_NAME = 'BOOLEANCODE' THEN 1 ELSE 0 END),
                @has_codeid = MAX(CASE
                        WHEN c.COLUMN_NAME LIKE '%CODEID'
                         AND c.COLUMN_NAME <> 'CODETABLECATALOGID'
                        THEN 1 ELSE 0 END)
        FROM
                INFORMATION_SCHEMA.COLUMNS c
        WHERE
                c.TABLE_NAME = @phys_raw;

        SET @data_type =
                CASE @cat_dtcode
                        WHEN 0 THEN N'Text'
                        WHEN 1 THEN N'Number'
                        WHEN 2 THEN N'Date'
                        WHEN 3 THEN N'Currency'
                        WHEN 4 THEN N'Code Table'
                        WHEN 5 THEN N'Yes/No'
                        ELSE N'Other'
                END;

        -- Initialize all value slots to NULL; the chosen branch fills its own.
        SET @value_text   = N'CAST(NULL AS NVARCHAR(MAX))';
        SET @value_bool   = N'CAST(NULL AS BIT)';
        SET @value_date   = N'CAST(NULL AS DATE)';
        SET @value_number = N'CAST(NULL AS DECIMAL(18,4))';
        SET @value_join   = N'';

        DECLARE @resolved BIT = 0;

        -- Prefer the column shape that matches the catalog's intent
        -- (DATATYPECODE). Some Altru tables carry redundant columns (for
        -- example a Code Table category whose physical table also has
        -- BOOLEANCODE); honoring the catalog avoids cross-contamination.
        IF @resolved = 0 AND @cat_dtcode = 5 AND @has_boolean = 1
        BEGIN
                SET @value_text = N'CASE av.BOOLEANCODE WHEN 1 THEN N''Yes'' WHEN 0 THEN N''No'' ELSE NULL END';
                SET @value_bool = N'av.BOOLEANCODE';
                SET @resolved   = 1;
        END;

        IF @resolved = 0 AND @cat_dtcode = 4 AND @has_codeid = 1
        BEGIN
                SELECT TOP 1 @code_column = QUOTENAME(c.COLUMN_NAME)
                FROM INFORMATION_SCHEMA.COLUMNS c
                WHERE c.TABLE_NAME = @phys_raw
                  AND c.COLUMN_NAME LIKE '%CODEID'
                  AND c.COLUMN_NAME <> 'CODETABLECATALOGID';

                IF @code_table IS NOT NULL AND @code_column IS NOT NULL
                BEGIN
                        SET @value_text = N'ct.DESCRIPTION';
                        SET @value_join =
                            N' LEFT JOIN ' + @code_table +
                            N' ct ON ct.ID = av.' + @code_column;
                        SET @resolved   = 1;
                END
                ELSE IF @code_column IS NOT NULL
                BEGIN
                        SET @value_text = N'CAST(av.' + @code_column + N' AS NVARCHAR(MAX))';
                        SET @resolved   = 1;
                END;
        END;

        IF @resolved = 0 AND @cat_dtcode = 2 AND @has_value_date = 1
        BEGIN
                SET @value_text   = N'CONVERT(NVARCHAR(10), av.VALUE, 23)';
                SET @value_date   = N'CAST(av.VALUE AS DATE)';
                SET @resolved     = 1;
        END;

        IF @resolved = 0 AND @cat_dtcode IN (1, 3) AND @has_value_numeric = 1
        BEGIN
                SET @value_text   = N'CAST(av.VALUE AS NVARCHAR(MAX))';
                SET @value_number = N'CAST(av.VALUE AS DECIMAL(18,4))';
                SET @resolved     = 1;
        END;

        IF @resolved = 0 AND @cat_dtcode = 0 AND @has_value_text = 1
        BEGIN
                SET @value_text = N'CAST(av.VALUE AS NVARCHAR(MAX))';
                SET @resolved   = 1;
        END;

        -- Fallback: catalog datatype does not match column shape. Pick the
        -- best-available column so the row is not lost AND override the
        -- Data_Type__c label so downstream consumers see the actual value
        -- semantics rather than the misleading catalog intent.
        IF @resolved = 0 AND @has_boolean = 1
        BEGIN
                SET @value_text = N'CASE av.BOOLEANCODE WHEN 1 THEN N''Yes'' WHEN 0 THEN N''No'' ELSE NULL END';
                SET @value_bool = N'av.BOOLEANCODE';
                SET @data_type  = N'Yes/No';
                SET @resolved   = 1;
        END;

        IF @resolved = 0 AND @has_codeid = 1
        BEGIN
                SELECT TOP 1 @code_column = QUOTENAME(c.COLUMN_NAME)
                FROM INFORMATION_SCHEMA.COLUMNS c
                WHERE c.TABLE_NAME = @phys_raw
                  AND c.COLUMN_NAME LIKE '%CODEID'
                  AND c.COLUMN_NAME <> 'CODETABLECATALOGID';

                IF @code_table IS NOT NULL AND @code_column IS NOT NULL
                BEGIN
                        SET @value_text = N'ct.DESCRIPTION';
                        SET @value_join =
                            N' LEFT JOIN ' + @code_table +
                            N' ct ON ct.ID = av.' + @code_column;
                        SET @data_type  = N'Code Table';
                        SET @resolved   = 1;
                END
                ELSE IF @code_column IS NOT NULL
                BEGIN
                        SET @value_text = N'CAST(av.' + @code_column + N' AS NVARCHAR(MAX))';
                        SET @data_type  = N'Code Table';
                        SET @resolved   = 1;
                END;
        END;

        IF @resolved = 0 AND @has_value_date = 1
        BEGIN
                SET @value_text = N'CONVERT(NVARCHAR(10), av.VALUE, 23)';
                SET @value_date = N'CAST(av.VALUE AS DATE)';
                SET @data_type  = N'Date';
                SET @resolved   = 1;
        END;

        IF @resolved = 0 AND @has_value_numeric = 1
        BEGIN
                SET @value_text   = N'CAST(av.VALUE AS NVARCHAR(MAX))';
                SET @value_number = N'CAST(av.VALUE AS DECIMAL(18,4))';
                -- Keep Currency vs Number distinction from the catalog when
                -- the dispatch landed on numeric; otherwise default to
                -- Number.
                SET @data_type    = CASE WHEN @cat_dtcode = 3 THEN N'Currency' ELSE N'Number' END;
                SET @resolved     = 1;
        END;

        IF @resolved = 0 AND @has_value_text = 1
        BEGIN
                SET @value_text = N'CAST(av.VALUE AS NVARCHAR(MAX))';
                SET @data_type  = N'Text';
                SET @resolved   = 1;
        END;

        IF @resolved = 0
        BEGIN
                -- No usable value column. Keep the row so the audit columns
                -- (Start/End, Comment, Source_Category_ID__c) still carry
                -- signal; mark the data type as Other.
                SET @data_type = N'Other';
        END;

        SET @branches = @branches + N'
SELECT
        av.ID                      AS Implementation_External_ID__c,
        av.CONSTITUENTID           AS source_constituent_id,
        N''' + REPLACE(@cat_name, '''', '''''') + N'''  AS Attribute_Name__c,
        ' + CASE WHEN @cat_group IS NULL
                 THEN N'CAST(NULL AS NVARCHAR(100))'
                 ELSE N'N''' + REPLACE(@cat_group, '''', '''''') + N''''
            END + N'              AS Attribute_Group__c,
        N''' + @data_type + N'''   AS Data_Type__c,
        ' + @value_text   + N' AS Value_Text__c,
        ' + @value_bool   + N' AS Value_Boolean__c,
        ' + @value_date   + N' AS Value_Date__c,
        ' + @value_number + N' AS Value_Number__c,
        av.COMMENT                 AS Comment__c,
        CAST(av.STARTDATE AS DATE) AS Start_Date__c,
        CAST(av.ENDDATE   AS DATE) AS End_Date__c,
        CAST(''' + CAST(@cat_id AS NVARCHAR(36)) + N''' AS UNIQUEIDENTIFIER)
                                   AS Source_Category_ID__c,
        ' + CASE WHEN @code_raw IS NULL
                 THEN N'CAST(NULL AS NVARCHAR(128))'
                 ELSE N'N''' + REPLACE(@code_raw, '''', '''''') + N''''
            END + N'              AS Source_Code_Table__c,
        av.DATEADDED               AS source_date_added
FROM ' + @phys_table + N' av' + @value_join + N'
UNION ALL';

        FETCH NEXT FROM cur
        INTO @cat_id, @cat_name, @cat_group, @cat_dtcode,
             @phys_table, @phys_raw, @code_table, @code_raw;
END;

CLOSE cur;
DEALLOCATE cur;

IF LEN(@branches) = 0
BEGIN
        -- No active constituent categories on this backup. Return an empty
        -- result with the expected schema so the extractor can iterate over
        -- zero rows without failing.
        SELECT
                CAST(NULL AS UNIQUEIDENTIFIER) AS Implementation_External_ID__c,
                CAST(NULL AS UNIQUEIDENTIFIER) AS Contact__c,
                CAST(NULL AS UNIQUEIDENTIFIER) AS Household_Organization__c,
                CAST(NULL AS NVARCHAR(100))    AS Attribute_Name__c,
                CAST(NULL AS NVARCHAR(100))    AS Attribute_Group__c,
                CAST(NULL AS NVARCHAR(20))     AS Data_Type__c,
                CAST(NULL AS NVARCHAR(MAX))    AS Value_Text__c,
                CAST(NULL AS BIT)              AS Value_Boolean__c,
                CAST(NULL AS DATE)             AS Value_Date__c,
                CAST(NULL AS DECIMAL(18,4))    AS Value_Number__c,
                CAST(NULL AS NVARCHAR(MAX))    AS Comment__c,
                CAST(NULL AS DATE)             AS Start_Date__c,
                CAST(NULL AS DATE)             AS End_Date__c,
                CAST(NULL AS UNIQUEIDENTIFIER) AS Source_Category_ID__c,
                CAST(NULL AS NVARCHAR(128))    AS Source_Code_Table__c
        WHERE 1 = 0;
        RETURN;
END;

SET @branches = LEFT(@branches, LEN(@branches) - LEN(N'UNION ALL'));

DECLARE @sql NVARCHAR(MAX) = N'
;WITH attribute_values AS (' + @branches + N')
SELECT
        av.Implementation_External_ID__c,
        CASE WHEN c.ISCONSTITUENT = 1
              AND c.ISGROUP        = 0
              AND c.ISORGANIZATION = 0
             THEN c.ID
             ELSE NULL
        END                                                  AS Contact__c,
        CASE WHEN c.ISGROUP = 1 OR c.ISORGANIZATION = 1
             THEN c.ID
             ELSE ch.HOUSEHOLDID
        END                                                  AS Household_Organization__c,
        av.Attribute_Name__c,
        av.Attribute_Group__c,
        av.Data_Type__c,
        av.Value_Text__c,
        av.Value_Boolean__c,
        av.Value_Date__c,
        av.Value_Number__c,
        av.Comment__c,
        av.Start_Date__c,
        av.End_Date__c,
        av.Source_Category_ID__c,
        av.Source_Code_Table__c
FROM
        attribute_values av
JOIN CONSTITUENT c
        ON c.ID = av.source_constituent_id
LEFT JOIN CONSTITUENTHOUSEHOLD ch
        ON ch.ID = c.ID
WHERE
        (@useDateFrom = 0 OR CAST(av.source_date_added AS DATE) >= @filterDateFrom)
    AND (@useDateTo   = 0 OR CAST(av.source_date_added AS DATE) <= @filterDateTo)
OPTION (RECOMPILE);';

INSERT INTO #out EXEC sp_executesql
        @sql,
        N'@useDateFrom BIT, @useDateTo BIT, @filterDateFrom DATE, @filterDateTo DATE',
        @useDateFrom    = @useDateFrom,
        @useDateTo      = @useDateTo,
        @filterDateFrom = @filterDateFrom,
        @filterDateTo   = @filterDateTo;

/* ============================================================ */
/* Aggregations for Scenarios 2 & 3                              */
/* ============================================================ */

PRINT '=== S2.a total emitted rows (expected ~62,647 per PR baseline) ===';
SELECT COUNT(*) AS total_emitted FROM #out;

PRINT '=== S2.b routing distribution (contact_only / household_only / both / neither) ===';
SELECT
    SUM(CASE WHEN Contact__c IS NOT NULL AND Household_Organization__c IS NULL  THEN 1 ELSE 0 END) AS contact_only,
    SUM(CASE WHEN Contact__c IS NULL     AND Household_Organization__c IS NOT NULL THEN 1 ELSE 0 END) AS household_only,
    SUM(CASE WHEN Contact__c IS NOT NULL AND Household_Organization__c IS NOT NULL THEN 1 ELSE 0 END) AS both_populated,
    SUM(CASE WHEN Contact__c IS NULL     AND Household_Organization__c IS NULL  THEN 1 ELSE 0 END) AS neither_populated
FROM #out;

PRINT '=== S2.c grain check (distinct External_ID == count(*); duplicates must be 0) ===';
SELECT
    COUNT(*)                                AS total_rows,
    COUNT(DISTINCT Implementation_External_ID__c) AS distinct_external_ids,
    COUNT(*) - COUNT(DISTINCT Implementation_External_ID__c) AS duplicates
FROM #out;

PRINT '=== S2.d typed slot integrity by Data_Type__c ===';
SELECT
    Data_Type__c,
    COUNT(*)                                                       AS n,
    SUM(CASE WHEN Value_Text__c     IS NOT NULL THEN 1 ELSE 0 END) AS with_text,
    SUM(CASE WHEN Value_Boolean__c  IS NOT NULL THEN 1 ELSE 0 END) AS with_bool,
    SUM(CASE WHEN Value_Date__c     IS NOT NULL THEN 1 ELSE 0 END) AS with_date,
    SUM(CASE WHEN Value_Number__c   IS NOT NULL THEN 1 ELSE 0 END) AS with_number,
    SUM(CASE WHEN Value_Text__c     IS NULL
              AND Value_Boolean__c  IS NULL
              AND Value_Date__c     IS NULL
              AND Value_Number__c   IS NULL THEN 1 ELSE 0 END)     AS all_slots_null
FROM #out
GROUP BY Data_Type__c
ORDER BY Data_Type__c;

PRINT '=== S2.e typed slot violations (counts that should be 0) ===';
SELECT
    SUM(CASE WHEN Data_Type__c = 'Yes/No'  AND Value_Boolean__c IS NULL THEN 1 ELSE 0 END) AS v_yesno_missing_bool,
    SUM(CASE WHEN Data_Type__c = 'Yes/No'  AND (Value_Date__c IS NOT NULL OR Value_Number__c IS NOT NULL) THEN 1 ELSE 0 END) AS v_yesno_extra_slot,
    SUM(CASE WHEN Data_Type__c = 'Date'    AND Value_Date__c IS NULL THEN 1 ELSE 0 END) AS v_date_missing,
    SUM(CASE WHEN Data_Type__c = 'Date'    AND (Value_Boolean__c IS NOT NULL OR Value_Number__c IS NOT NULL) THEN 1 ELSE 0 END) AS v_date_extra_slot,
    SUM(CASE WHEN Data_Type__c IN ('Number','Currency') AND Value_Number__c IS NULL THEN 1 ELSE 0 END) AS v_num_missing,
    SUM(CASE WHEN Data_Type__c IN ('Number','Currency') AND (Value_Boolean__c IS NOT NULL OR Value_Date__c IS NOT NULL) THEN 1 ELSE 0 END) AS v_num_extra_slot,
    SUM(CASE WHEN Data_Type__c = 'Text'    AND Value_Text__c IS NULL THEN 1 ELSE 0 END) AS v_text_missing,
    SUM(CASE WHEN Data_Type__c = 'Text'    AND (Value_Boolean__c IS NOT NULL OR Value_Date__c IS NOT NULL OR Value_Number__c IS NOT NULL) THEN 1 ELSE 0 END) AS v_text_extra_slot
FROM #out;

PRINT '=== S3.a Source category traceability: number of distinct Source_Category_ID__c values emitted (should be <= 103 active categorias) ===';
SELECT COUNT(DISTINCT Source_Category_ID__c) AS distinct_source_categories FROM #out;

PRINT '=== S3.b Categories with rows emitted (should match the universe minus orphan/flagged/non-constituent-scoped) ===';
SELECT
    SUM(CASE WHEN ac.FLAGGEDFORDELETE = 1               THEN 1 ELSE 0 END) AS v_flagged_emitted,
    SUM(CASE WHEN ac.FLAGGEDFOREXTENSIONREMOVAL = 1     THEN 1 ELSE 0 END) AS v_flaggedremoval_emitted,
    SUM(CASE WHEN it.TABLE_NAME IS NULL                 THEN 1 ELSE 0 END) AS v_orphan_emitted,
    SUM(CASE WHEN ic.COLUMN_NAME IS NULL                THEN 1 ELSE 0 END) AS v_no_constituentid_col_emitted
FROM (SELECT DISTINCT Source_Category_ID__c AS catid FROM #out) o
JOIN ATTRIBUTECATEGORY ac ON ac.ID = o.catid
LEFT JOIN TABLECATALOG tc ON tc.ID = ac.TABLECATALOGID
LEFT JOIN INFORMATION_SCHEMA.TABLES it ON it.TABLE_NAME = tc.TABLENAME
LEFT JOIN INFORMATION_SCHEMA.COLUMNS ic ON ic.TABLE_NAME = tc.TABLENAME AND ic.COLUMN_NAME = 'CONSTITUENTID';

DROP TABLE #out;
