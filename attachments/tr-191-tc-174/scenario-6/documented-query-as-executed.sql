-- Disposition of every suggestion a batch EVER SHOWED, per daily batch, per owner.
--
-- count(DISTINCT i.action_id), not count(*): membership is append-only and a
-- suggestion can be a member of the same batch more than once (a forced
-- regeneration reuses the batch row and may re-add what it just released). The
-- disposition is a property of the SUGGESTION, so each one counts once.
--
-- The buckets are mutually exclusive and exhaustive. Walking the tree: deleted_at
-- set is `ignored` whatever the state; then expired_at set is `expired`; then an
-- accepted state is `accepted`; then a still-Suggested row is `still_pending` or
-- `released` depending on whether THIS batch is the one still showing it; and a
-- bare `Rejected` with neither timestamp is `unaccounted` — a shape no
-- disposition describes, which sf-cases-worker can produce (BACKLOG #5). It
-- should be 0, and it is selected rather than assumed so the number is visible
-- instead of missing.
SELECT
    b.owner_id,
    b.batch_date,
    count(DISTINCT i.action_id) AS total,
    count(DISTINCT i.action_id) FILTER (
        WHERE cta.deleted_at IS NULL
          AND cta.expired_at IS NULL
          AND cta.state IN ('New', 'In_progress', 'Done')
    ) AS accepted,
    count(DISTINCT i.action_id) FILTER (
        WHERE cta.deleted_at IS NOT NULL
    ) AS ignored,
    count(DISTINCT i.action_id) FILTER (
        WHERE cta.expired_at IS NOT NULL AND cta.deleted_at IS NULL
    ) AS expired,
    count(DISTINCT i.action_id) FILTER (
        WHERE cta.state = 'Suggested'
          AND cta.deleted_at IS NULL
          AND cta.expired_at IS NULL
          AND cta.suggestion_batch_id = b.id
    ) AS still_pending,
    -- Shown by this batch, never actioned, and this batch no longer shows it:
    -- either R11 handed it back to the candidate pool or a later batch carried it
    -- over. `task_suggestion_batch_items.release_reason` separates those two for
    -- anyone who needs it; this bucket deliberately does not, because both mean
    -- "the CSM did not answer" and neither is a decision.
    count(DISTINCT i.action_id) FILTER (
        WHERE cta.state = 'Suggested'
          AND cta.deleted_at IS NULL
          AND cta.expired_at IS NULL
          AND cta.suggestion_batch_id IS DISTINCT FROM b.id
    ) AS released,
    count(DISTINCT i.action_id) FILTER (
        WHERE cta.state = 'Rejected'
          AND cta.deleted_at IS NULL
          AND cta.expired_at IS NULL
    ) AS unaccounted
FROM csm_os.task_suggestion_batches b
JOIN csm_os.task_suggestion_batch_items i ON i.batch_id = b.id
JOIN csm_os.control_tower_actions cta ON cta.id = i.action_id
GROUP BY b.owner_id, b.batch_date
ORDER BY b.batch_date DESC;

