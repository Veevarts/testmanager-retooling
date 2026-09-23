-- TC-177 escenario 6 — reservas con varios itinerarios cuyos tipos de grupo no coinciden.
-- Ni el ticket ni el comentario de causa raiz dicen que deberia pasar en ese caso.
-- Solo lectura. Salida puramente numerica.
WITH PerRes AS (
    SELECT it.RESERVATIONID,
           COUNT(1) AS itinerary_rows,
           COUNT(DISTINCT CASE WHEN gstc.DESCRIPTION IS NOT NULL
                               THEN gstc.DESCRIPTION END) AS distinct_named_types,
           SUM(CASE WHEN LOWER(gstc.DESCRIPTION) LIKE '%group%'
                    THEN 1 ELSE 0 END) AS groupish_rows,
           SUM(CASE WHEN gstc.DESCRIPTION IS NOT NULL
                     AND LOWER(gstc.DESCRIPTION) NOT LIKE '%group%'
                    THEN 1 ELSE 0 END) AS named_non_groupish_rows,
           SUM(CASE WHEN gstc.DESCRIPTION IS NULL THEN 1 ELSE 0 END) AS untyped_rows
    FROM ITINERARY it
    LEFT JOIN GROUPSALESGROUPTYPECODE gstc ON gstc.ID = it.GROUPSALESGROUPTYPECODEID
    GROUP BY it.RESERVATIONID
)
SELECT
  COUNT(1)                                                              AS reservations_with_itinerary,
  SUM(CASE WHEN itinerary_rows > 1 THEN 1 ELSE 0 END)                   AS multi_itinerary,
  SUM(CASE WHEN distinct_named_types > 1 THEN 1 ELSE 0 END)             AS several_distinct_named_types,
  SUM(CASE WHEN groupish_rows > 0 AND named_non_groupish_rows > 0
           THEN 1 ELSE 0 END)                                           AS conflict_groupish_vs_named_other,
  SUM(CASE WHEN groupish_rows > 0 AND untyped_rows > 0
           THEN 1 ELSE 0 END)                                           AS conflict_groupish_vs_untyped,
  SUM(CASE WHEN named_non_groupish_rows > 0 AND untyped_rows > 0
           THEN 1 ELSE 0 END)                                           AS conflict_named_other_vs_untyped
FROM PerRes;
