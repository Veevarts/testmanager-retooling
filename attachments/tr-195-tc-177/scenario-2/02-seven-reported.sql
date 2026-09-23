-- TC-177 escenario 2 — las siete reservas del reporte, PRE vs POST.
-- Solo lectura. Salida puramente numerica: ningun nombre ni factura sale de la base.
WITH Seven AS (
    SELECT CAST(v AS UNIQUEIDENTIFIER) AS RID FROM (VALUES
        ('2758E18C-0F18-4A01-ACED-265D3BFCC5D2'),
        ('3FBD520F-45CF-4B77-B518-75ECCA16E09A'),
        ('24A7D059-BA24-4A57-A7A5-18DB3121EBF4'),
        ('E37DE412-85A8-4C8D-B9AF-04AA6C0C5F8B'),
        ('E22411F3-25BB-44B7-A65C-6AE894AA598D'),
        ('421D2C20-2255-4E28-9E66-1B9D6CA27463'),
        ('68152E1B-2EC5-44D6-852A-FAC213BDE8CB')
    ) AS t(v)
),
OldTypes AS (
    SELECT it.RESERVATIONID,
           CASE WHEN SUM(CASE WHEN LOWER(gstc.DESCRIPTION) LIKE '%group%' THEN 1 ELSE 0 END) > 0
                THEN 'Group' ELSE 'Rental_Event' END AS reservationType
    FROM ITINERARY it
    LEFT JOIN GROUPSALESGROUPTYPECODE gstc ON gstc.ID = it.GROUPSALESGROUPTYPECODEID
    GROUP BY it.RESERVATIONID
),
NewTypes AS (
    SELECT r.ID AS RESERVATIONID,
           CASE WHEN SUM(CASE WHEN LOWER(gstc.DESCRIPTION) LIKE '%group%' THEN 1 ELSE 0 END) > 0
                THEN 'Group' ELSE 'Rental_Event' END AS reservationType
    FROM RESERVATION r
    LEFT JOIN ITINERARY it ON it.RESERVATIONID = r.ID
    LEFT JOIN GROUPSALESGROUPTYPECODE gstc ON gstc.ID = it.GROUPSALESGROUPTYPECODEID
    GROUP BY r.ID
)
SELECT
  (SELECT COUNT(1) FROM Seven)                                              AS reported_ids,
  SUM(CASE WHEN r.ID IS NOT NULL THEN 1 ELSE 0 END)                         AS found_in_source,
  SUM(CASE WHEN o.reservationType IS NULL THEN 1 ELSE 0 END)                AS pre_blank,
  SUM(CASE WHEN o.reservationType = 'Group' THEN 1 ELSE 0 END)              AS pre_group,
  SUM(CASE WHEN o.reservationType = 'Rental_Event' THEN 1 ELSE 0 END)       AS pre_rental,
  SUM(CASE WHEN n.reservationType = 'Rental_Event' THEN 1 ELSE 0 END)       AS post_rental,
  SUM(CASE WHEN n.reservationType = 'Group' THEN 1 ELSE 0 END)              AS post_group,
  SUM(CASE WHEN n.reservationType IS NULL THEN 1 ELSE 0 END)                AS post_blank,
  (SELECT COUNT(1) FROM ITINERARY i2 JOIN Seven s2 ON s2.RID = i2.RESERVATIONID) AS itineraries_total
FROM Seven s
LEFT JOIN RESERVATION r ON r.ID = s.RID
LEFT JOIN OldTypes o    ON o.RESERVATIONID = s.RID
LEFT JOIN NewTypes n    ON n.RESERVATIONID = s.RID;
