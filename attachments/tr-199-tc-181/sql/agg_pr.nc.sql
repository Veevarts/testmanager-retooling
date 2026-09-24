WITH q AS (
SELECT
        csc.ID AS Implementation_External_ID__c,
        CASE
                WHEN c.ISORGANIZATION = 0
                     AND c.ISGROUP = 0
                     AND c.ISCONSTITUENT = 1
                THEN c.ID
                ELSE NULL
        END AS Contact__c,
        CASE
                WHEN c.ISORGANIZATION = 1
                     OR c.ISGROUP = 1
                THEN c.ID
                ELSE NULL
        END AS Household_Organization__c,
        c.ID AS ConstituentID,
        c.NAME AS ConstituentName,
        sc.ID AS SolicitCodeID,
        sc.DESCRIPTION AS SolicitCodeDescription,
        sc.ACTIVE AS SolicitCodeActive,
        sc.SITEID AS SolicitCodeSiteID,
        sc.EXCLUSIONCODE AS SolicitCodeExclusionCode,
        sc.EXCLUSION AS SolicitCodeExclusion,
        csc.STARTDATE AS ConstituentSolicitCodeStartDate,
        csc.ENDDATE AS ConstituentSolicitCodeEndDate
FROM CONSTITUENTSOLICITCODE csc
        JOIN CONSTITUENT c ON
                c.ID = csc.CONSTITUENTID
        JOIN SOLICITCODE sc ON
                sc.ID = csc.SOLICITCODEID
)
SELECT
    COUNT(*)                                        AS Filas,
    COUNT(DISTINCT Implementation_External_ID__c)   AS IdsExternosDistintos,
    SUM(CASE WHEN Contact__c IS NOT NULL THEN 1 ELSE 0 END)                AS ConContacto,
    SUM(CASE WHEN Household_Organization__c IS NOT NULL THEN 1 ELSE 0 END) AS ConOrganizacion,
    SUM(CASE WHEN Contact__c IS NOT NULL AND Household_Organization__c IS NOT NULL THEN 1 ELSE 0 END) AS ConLasDos,
    SUM(CASE WHEN Contact__c IS NULL AND Household_Organization__c IS NULL THEN 1 ELSE 0 END)         AS SinNinguna,
    COUNT(DISTINCT Household_Organization__c)       AS EntidadesOrganizacionDistintas,
    COUNT(DISTINCT CAST(ConstituentID AS VARCHAR(36)) + '|' + CAST(SolicitCodeID AS VARCHAR(36))) AS ParesDistintos
FROM q;