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
        sc.ID AS SolicitCodeID,
        csc.STARTDATE AS StartDate,
        csc.ENDDATE AS EndDate
FROM CONSTITUENTSOLICITCODE csc
        JOIN CONSTITUENT c ON
                c.ID = csc.CONSTITUENTID
        JOIN SOLICITCODE sc ON
                sc.ID = csc.SOLICITCODEID
),
Dup AS (
    SELECT ConstituentID, SolicitCodeID, COUNT(*) AS Filas
    FROM q GROUP BY ConstituentID, SolicitCodeID HAVING COUNT(*) > 1
),
DupConFechas AS (
    SELECT ConstituentID, SolicitCodeID, StartDate, EndDate, COUNT(*) AS Filas
    FROM q GROUP BY ConstituentID, SolicitCodeID, StartDate, EndDate HAVING COUNT(*) > 1
)
SELECT
    (SELECT COUNT(*) FROM Dup)                                   AS ParesRepetidos,
    (SELECT ISNULL(SUM(Filas), 0) FROM Dup)                      AS FilasEnParesRepetidos,
    (SELECT COUNT(*) FROM DupConFechas)                          AS ParesRepetidosAunConFechas,
    (SELECT ISNULL(SUM(Filas), 0) FROM DupConFechas)             AS FilasAunAmbiguasConFechas,
    (SELECT COUNT(*) FROM q
      WHERE ConstituentID = '2E68B251-61E6-4668-98C3-ECDBEFBBC2DE')  AS Ejemplo1Filas,
    (SELECT COUNT(*) FROM q
      WHERE ConstituentID = '2E68B251-61E6-4668-98C3-ECDBEFBBC2DE'
        AND Contact__c IS NOT NULL
        AND Household_Organization__c IS NULL)                      AS Ejemplo1ConContactoSoloContacto,
    (SELECT COUNT(*) FROM q
      WHERE ConstituentID = 'B14F7EB8-1C1B-4EDC-A627-3194AA5C272E')  AS Ejemplo2Filas,
    (SELECT COUNT(*) FROM q
      WHERE ConstituentID = 'B14F7EB8-1C1B-4EDC-A627-3194AA5C272E'
        AND Contact__c IS NOT NULL
        AND Household_Organization__c IS NULL)                      AS Ejemplo2ConContactoSoloContacto,
    (SELECT COUNT(*) FROM q
      WHERE SolicitCodeID = '333F7D7F-833A-4ECE-8D44-5D3C80E363E0')  AS FilasDelCodigoDelTicket;
