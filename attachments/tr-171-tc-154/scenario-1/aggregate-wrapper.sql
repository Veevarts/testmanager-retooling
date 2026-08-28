-- IM-1211 aggregate wrapper: quantify the notes-source coverage before/after
-- the PR #176 fix. Numeric-only, contract-safe, revert-proof at contract level.
-- Runs against any Altru profile. Expected illinois_2 (dev PR body): 1,599
-- reservations with any note content, 315 with 2+ sources.

WITH note_sources AS (
    SELECT
        r.ID AS RESERVATIONID,
        CASE WHEN so.COMMENTS IS NOT NULL AND LTRIM(RTRIM(so.COMMENTS)) <> ''
             THEN 1 ELSE 0 END AS has_important_notes,
        CASE WHEN r.ARRIVALNOTES IS NOT NULL AND LTRIM(RTRIM(r.ARRIVALNOTES)) <> ''
             THEN 1 ELSE 0 END AS has_arrival_notes,
        (SELECT MAX(CASE
                WHEN (rn.TEXTNOTE IS NOT NULL AND LTRIM(RTRIM(rn.TEXTNOTE)) <> '')
                  OR (rn.TITLE IS NOT NULL AND LTRIM(RTRIM(rn.TITLE)) <> '')
                THEN 1 ELSE 0 END)
         FROM RESERVATIONNOTE rn
         WHERE rn.RESERVATIONID = r.ID) AS has_reservation_notes,
        (SELECT MAX(CASE
                WHEN ii.NOTES IS NOT NULL AND LTRIM(RTRIM(ii.NOTES)) <> ''
                THEN 1 ELSE 0 END)
         FROM ITINERARY it
         INNER JOIN ITINERARYITEM ii ON ii.ITINERARYID = it.ID
         WHERE it.RESERVATIONID = r.ID) AS has_itinerary_notes
    FROM RESERVATION r
    LEFT JOIN SALESORDER so ON so.ID = r.SALESORDERID
)
SELECT
    COUNT(*) AS total_reservations,
    SUM(CASE WHEN COALESCE(has_important_notes, 0) = 1 THEN 1 ELSE 0 END) AS with_important_notes,
    SUM(CASE WHEN COALESCE(has_arrival_notes, 0) = 1 THEN 1 ELSE 0 END) AS with_arrival_notes,
    SUM(CASE WHEN COALESCE(has_reservation_notes, 0) = 1 THEN 1 ELSE 0 END) AS with_reservation_notes,
    SUM(CASE WHEN COALESCE(has_itinerary_notes, 0) = 1 THEN 1 ELSE 0 END) AS with_itinerary_notes,
    SUM(CASE WHEN COALESCE(has_important_notes, 0)
              + COALESCE(has_arrival_notes, 0)
              + COALESCE(has_reservation_notes, 0)
              + COALESCE(has_itinerary_notes, 0) >= 1 THEN 1 ELSE 0 END) AS with_any_note,
    SUM(CASE WHEN COALESCE(has_important_notes, 0)
              + COALESCE(has_arrival_notes, 0)
              + COALESCE(has_reservation_notes, 0)
              + COALESCE(has_itinerary_notes, 0) >= 2 THEN 1 ELSE 0 END) AS with_two_or_more_sources,
    -- PRE-fix coverage: only RESERVATIONNOTE was mapped
    SUM(CASE WHEN COALESCE(has_reservation_notes, 0) = 1 THEN 1 ELSE 0 END) AS pre_fix_coverage_count,
    -- POST-fix coverage: any of the 4 sources
    SUM(CASE WHEN COALESCE(has_important_notes, 0)
              + COALESCE(has_arrival_notes, 0)
              + COALESCE(has_reservation_notes, 0)
              + COALESCE(has_itinerary_notes, 0) >= 1 THEN 1 ELSE 0 END) AS post_fix_coverage_count
FROM note_sources;
