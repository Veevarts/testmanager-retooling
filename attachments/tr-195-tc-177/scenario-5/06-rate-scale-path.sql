-- TC-177 escenario 5 — la causa raiz dice que no hay tipo de grupo por NINGUN otro camino.
-- Se comprueba el camino de la escala de tarifa (RESERVATIONRATESCALE -> RATESCALE),
-- que es el que el comentario del 17-09-2026 declara haber revisado.
-- Se mide sobre las 7 reportadas Y sobre las 34 que hoy salen en blanco.
-- Si alguna de las 34 tuviera tipo de grupo por ahi, clasificarla Rental_Event
-- estaria perdiendo un dato real, y eso seria un defecto del arreglo.
-- Solo lectura. Salida puramente numerica.
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
Blanks AS (
    SELECT r.ID AS RID
    FROM RESERVATION r
    LEFT JOIN ITINERARY it ON it.RESERVATIONID = r.ID
    WHERE it.ID IS NULL
),
RateScalePath AS (
    SELECT rrs.ID AS RID,
           rs.GROUPSALESGROUPTYPECODEID AS gst_id,
           gstc.DESCRIPTION AS gst_desc
    FROM RESERVATIONRATESCALE rrs
    LEFT JOIN RATESCALE rs ON rs.ID = rrs.RATESCALEID
    LEFT JOIN GROUPSALESGROUPTYPECODE gstc ON gstc.ID = rs.GROUPSALESGROUPTYPECODEID
)
SELECT
  'seven_reported' AS cohort,
  COUNT(1)                                                               AS cohort_size,
  SUM(CASE WHEN p.RID IS NOT NULL THEN 1 ELSE 0 END)                     AS has_rate_scale_row,
  SUM(CASE WHEN p.gst_id IS NOT NULL THEN 1 ELSE 0 END)                  AS has_rate_scale_group_type,
  SUM(CASE WHEN LOWER(p.gst_desc) LIKE '%group%' THEN 1 ELSE 0 END)      AS rate_scale_says_group
FROM Seven s
LEFT JOIN RateScalePath p ON p.RID = s.RID

UNION ALL

SELECT
  'blank_today' AS cohort,
  COUNT(1)                                                               AS cohort_size,
  SUM(CASE WHEN p.RID IS NOT NULL THEN 1 ELSE 0 END)                     AS has_rate_scale_row,
  SUM(CASE WHEN p.gst_id IS NOT NULL THEN 1 ELSE 0 END)                  AS has_rate_scale_group_type,
  SUM(CASE WHEN LOWER(p.gst_desc) LIKE '%group%' THEN 1 ELSE 0 END)      AS rate_scale_says_group
FROM Blanks b
LEFT JOIN RateScalePath p ON p.RID = b.RID;
