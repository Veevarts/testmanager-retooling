-- TC-177 escenario 5 — estado e importes de las reservas reportadas que siguen existiendo.
-- La causa raiz afirma: "empty or abandoned bookings: no itinerary, no order items,
-- $0 amount, status Pending or Cancelled (4 Cancelled, 3 Pending)".
-- Solo lectura.
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
Latest AS (
    SELECT h.RESERVATIONID,
           h.STATUSCODE,
           h.STATUS,
           ROW_NUMBER() OVER (PARTITION BY h.RESERVATIONID
                              ORDER BY h.STATUSDATE DESC, h.DATEADDED DESC) AS rn
    FROM RESERVATIONSTATUSHISTORY h
    JOIN Seven s ON s.RID = h.RESERVATIONID
)
SELECT
    l.STATUSCODE,
    MAX(l.STATUS)                                         AS status_label,
    COUNT(1)                                              AS reservations,
    SUM(CASE WHEN r.DEPOSITAMOUNT = 0 OR r.DEPOSITAMOUNT IS NULL
             THEN 1 ELSE 0 END)                           AS zero_deposit,
    SUM(CASE WHEN r.SECURITYDEPOSITAMOUNT = 0 OR r.SECURITYDEPOSITAMOUNT IS NULL
             THEN 1 ELSE 0 END)                           AS zero_security_deposit
FROM Latest l
JOIN RESERVATION r ON r.ID = l.RESERVATIONID
WHERE l.rn = 1
GROUP BY l.STATUSCODE
ORDER BY l.STATUSCODE;
