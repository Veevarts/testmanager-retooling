WITH rental_linked AS (
    SELECT so.ID AS soid,
           so.STATUS AS sostatus,
           r.STARTDATETIME AS sdt,
           r.ARRIVALDATE AS adate,
           r.ARRIVALTIME AS atime
    FROM SALESORDER so
        JOIN RESERVATION r ON r.ID = so.ID
),
ticket_backed AS (
    SELECT soid, sostatus, sdt, adate, atime
    FROM rental_linked rl
    WHERE EXISTS (
        SELECT 1
        FROM SALESORDERITEM soi
            JOIN SALESORDERITEMTICKET soit ON soit.ID = soi.ID
        WHERE soi.SALESORDERID = rl.soid
    )
),
confirmed AS (
    SELECT soid, sdt, adate, atime
    FROM ticket_backed
    WHERE sostatus = 'Confirmed'
)
SELECT
    (SELECT COUNT(*) FROM rental_linked) AS orders_with_rental_event,
    (SELECT COUNT(*) FROM ticket_backed) AS ticket_backed_with_rental_event,
    (SELECT COUNT(*) FROM confirmed) AS confirmed_ticket_backed,
    (SELECT COUNT(*) FROM confirmed WHERE sdt IS NOT NULL) AS startdatetime_populated,
    (SELECT COUNT(*) FROM confirmed WHERE CAST(sdt AS DATE) = adate) AS date_eq_arrivaldate,
    (SELECT COUNT(*) FROM confirmed
        WHERE REPLACE(CONVERT(CHAR(5), CAST(sdt AS TIME), 108), ':', '') = atime) AS time_eq_arrivaltime,
    (SELECT COUNT(*) FROM confirmed WHERE CAST(sdt AS TIME) <> CAST('00:00:00' AS TIME)) AS real_time_of_day,
    (SELECT COUNT(*) FROM confirmed WHERE sdt IS NULL) AS confirmed_missing_instant,
    (SELECT COUNT(*) FROM confirmed WHERE atime = '') AS confirmed_blank_arrivaltime,
    (SELECT COUNT(*) FROM ticket_backed WHERE sostatus = 'Finalized') AS status_finalized_rows,
    (SELECT COUNT(DISTINCT sostatus) FROM ticket_backed) AS distinct_statuses
