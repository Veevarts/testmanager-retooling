-- TC-159 / IM-1224 — verificacion source-side de las afirmaciones del PR 179.
-- Solo lecturas agregadas sobre RESERVATION / SALESORDER / CONSTITUENT / RELATIONSHIP / GROUPMEMBER.

-- [1] Reparto de reservas por tipo de client, y cuantas de las organisation
--     llevan CONTACTRELATIONSHIPID (la columna que el fix empieza a usar).
SELECT
        CASE
                WHEN c.ID IS NULL THEN 'sin constituent'
                WHEN c.ISORGANIZATION = 1 THEN 'organisation'
                WHEN c.ISGROUP = 1 THEN 'household/group'
                WHEN c.ISCONSTITUENT = 1 THEN 'individual'
                ELSE 'otro'
        END AS ClientType,
        COUNT(*) AS Reservations,
        SUM(CASE WHEN so.CONTACTRELATIONSHIPID IS NOT NULL THEN 1 ELSE 0 END) AS WithContactRelationship
FROM RESERVATION r
INNER JOIN SALESORDER so ON so.ID = r.ID
LEFT JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID
GROUP BY
        CASE
                WHEN c.ID IS NULL THEN 'sin constituent'
                WHEN c.ISORGANIZATION = 1 THEN 'organisation'
                WHEN c.ISGROUP = 1 THEN 'household/group'
                WHEN c.ISCONSTITUENT = 1 THEN 'individual'
                ELSE 'otro'
        END;

-- [2] Las reservas que POST-fix siguen sin contact: el PR dice 768 organisation
--     sin CONTACTRELATIONSHIPID + 1 household sin primary member = 769.
SELECT
        'organisation sin CONTACTRELATIONSHIPID' AS Reason,
        COUNT(*) AS Reservations
FROM RESERVATION r
INNER JOIN SALESORDER so ON so.ID = r.ID
INNER JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID AND c.ISORGANIZATION = 1
WHERE so.CONTACTRELATIONSHIPID IS NULL
UNION ALL
SELECT
        'household sin primary member exportable' AS Reason,
        COUNT(*) AS Reservations
FROM RESERVATION r
INNER JOIN SALESORDER so ON so.ID = r.ID
INNER JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID AND c.ISORGANIZATION = 0 AND c.ISGROUP = 1
WHERE NOT EXISTS (
        SELECT 1
        FROM GROUPMEMBER gm
        INNER JOIN CONSTITUENT memc ON memc.ID = gm.MEMBERID
                AND memc.ISORGANIZATION = 0 AND memc.ISGROUP = 0 AND memc.ISCONSTITUENT = 1
        WHERE gm.GROUPID = c.ID AND gm.ISPRIMARY = 1
);

-- [3] Fan-out real: grupos con MAS DE UN primary member. Si existen y son clients
--     de reservas, el TOP 1 ... ORDER BY gm.ID es load-bearing (no cosmetico).
SELECT
        COUNT(*) AS GroupsWithMultiplePrimaryMembers,
        SUM(g.UsedAsReservationClient) AS OfThoseUsedAsReservationClient
FROM (
        SELECT
                gp.GROUPID,
                CASE WHEN EXISTS (
                        SELECT 1 FROM SALESORDER so2
                        INNER JOIN RESERVATION r2 ON r2.ID = so2.ID
                        WHERE so2.CONSTITUENTID = gp.GROUPID
                ) THEN 1 ELSE 0 END AS UsedAsReservationClient
        FROM (
                SELECT gm.GROUPID
                FROM GROUPMEMBER gm
                WHERE gm.ISPRIMARY = 1
                GROUP BY gm.GROUPID
                HAVING COUNT(*) > 1
        ) gp
) g;

-- [4] Anti-dangle load-bearing: contactos resueltos por la rama organisation que
--     NO cumplen el shape que exporta contact.sql (ISCONSTITUENT=1, ISGROUP=0,
--     ISORGANIZATION=0). Son los que el guard descarta; si es > 0, el guard evita
--     lookups colgados reales.
SELECT
        COUNT(*) AS OrgContactsRejectedByGuard
FROM RESERVATION r
INNER JOIN SALESORDER so ON so.ID = r.ID
INNER JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID AND c.ISORGANIZATION = 1
INNER JOIN RELATIONSHIP rel ON rel.ID = so.CONTACTRELATIONSHIPID
INNER JOIN CONSTITUENT relc ON relc.ID = rel.RECIPROCALCONSTITUENTID
WHERE NOT (relc.ISORGANIZATION = 0 AND relc.ISGROUP = 0 AND relc.ISCONSTITUENT = 1);

-- [5] As-stored: relationships usados como contacto que Altru NO validaria hoy
--     (ISCONTACT = 0 o ENDDATE pasado). El PR dice 36 y 20 en Long Island.
SELECT
        SUM(CASE WHEN rel.ISCONTACT = 0 THEN 1 ELSE 0 END) AS ContactsWithIsContactZero,
        SUM(CASE WHEN rel.ENDDATE IS NOT NULL AND rel.ENDDATE < GETDATE() THEN 1 ELSE 0 END) AS ContactsWithPastEndDate
FROM RESERVATION r
INNER JOIN SALESORDER so ON so.ID = r.ID
INNER JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID AND c.ISORGANIZATION = 1
INNER JOIN RELATIONSHIP rel ON rel.ID = so.CONTACTRELATIONSHIPID
INNER JOIN CONSTITUENT relc ON relc.ID = rel.RECIPROCALCONSTITUENTID
        AND relc.ISORGANIZATION = 0 AND relc.ISGROUP = 0 AND relc.ISCONSTITUENT = 1;

-- [6] Example 2: clients individuales cuyo Company/Household viene vacio.
--     El PR afirma que es ausencia de dato fuente: sin CONSTITUENTHOUSEHOLD y
--     sin llegar a un household via GROUPMEMBER.
SELECT
        COUNT(*) AS IndividualClientReservations,
        SUM(x.NoHouseholdRow) AS WithoutHouseholdRow,
        SUM(x.NoHouseholdButInAGroup) AS WithoutHouseholdButReachableViaGroupMember
FROM (
        SELECT
                CASE WHEN chh.ID IS NULL THEN 1 ELSE 0 END AS NoHouseholdRow,
                CASE WHEN chh.ID IS NULL AND EXISTS (
                        SELECT 1
                        FROM GROUPMEMBER gm
                        INNER JOIN CONSTITUENT gc ON gc.ID = gm.GROUPID AND gc.ISGROUP = 1
                        WHERE gm.MEMBERID = c.ID
                ) THEN 1 ELSE 0 END AS NoHouseholdButInAGroup
        FROM RESERVATION r
        INNER JOIN SALESORDER so ON so.ID = r.ID
        INNER JOIN CONSTITUENT c ON c.ID = so.CONSTITUENTID
                AND c.ISORGANIZATION = 0 AND c.ISGROUP = 0 AND c.ISCONSTITUENT = 1
        LEFT JOIN CONSTITUENTHOUSEHOLD chh ON chh.ID = so.CONSTITUENTID
) x;
