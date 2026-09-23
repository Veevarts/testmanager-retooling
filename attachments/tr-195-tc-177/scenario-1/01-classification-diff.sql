-- TC-177 / IM-1223 — clasificacion PRE (CTE enraizado en ITINERARY, rama base)
-- vs POST (CTE enraizado en RESERVATION, PR #184), en una sola pasada.
-- Solo lectura. Salida puramente numerica.
WITH OldTypes AS (
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
),
Joined AS (
    SELECT r.ID AS RID, o.reservationType AS old_type, n.reservationType AS new_type
    FROM RESERVATION r
    LEFT JOIN OldTypes o ON o.RESERVATIONID = r.ID
    LEFT JOIN NewTypes n ON n.RESERVATIONID = r.ID
)
SELECT
  COUNT(*)                                                                   AS total_reservations,
  COUNT(DISTINCT RID)                                                        AS distinct_reservations,
  SUM(CASE WHEN old_type IS NULL THEN 1 ELSE 0 END)                          AS pre_blank,
  SUM(CASE WHEN new_type IS NULL THEN 1 ELSE 0 END)                          AS post_blank,
  SUM(CASE WHEN old_type = 'Group' THEN 1 ELSE 0 END)                        AS pre_group,
  SUM(CASE WHEN new_type = 'Group' THEN 1 ELSE 0 END)                        AS post_group,
  SUM(CASE WHEN old_type = 'Rental_Event' THEN 1 ELSE 0 END)                 AS pre_rental,
  SUM(CASE WHEN new_type = 'Rental_Event' THEN 1 ELSE 0 END)                 AS post_rental,
  SUM(CASE WHEN old_type IS NOT NULL AND old_type <> new_type THEN 1 ELSE 0 END) AS changed_with_evidence,
  SUM(CASE WHEN old_type IS NULL AND new_type = 'Rental_Event' THEN 1 ELSE 0 END) AS blank_to_rental,
  SUM(CASE WHEN old_type IS NULL AND new_type = 'Group' THEN 1 ELSE 0 END)   AS blank_to_group,
  SUM(CASE WHEN new_type NOT IN ('Group','Rental_Event') THEN 1 ELSE 0 END)  AS post_outside_picklist
FROM Joined;
