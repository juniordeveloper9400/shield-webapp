-- ============================================================================
--  0006 · Move existing reward_points onto the ledger
-- ============================================================================
--  The reward-points balance is now the sum of app.reward_point_transaction
--  (see RewardsRepository / RewardsService in the app). Members who earned
--  points under the old flow have a figure in app.users.reward_points but no
--  ledger rows, so their balance would read as 0.
--
--  This writes one ADJUSTMENT row per such member for their current balance,
--  so nobody's points disappear when the app switches to the ledger.
--
--  Idempotent — a member who already has any ledger row is skipped:
--    dart run backend/db/apply_migration.dart backend/db/migrations/0006_backfill_reward_points_ledger.sql --yes
-- ============================================================================

SET search_path TO app, public;

INSERT INTO app.reward_point_transaction (member_id, points, reason, note)
SELECT u.id, u.reward_points, 'ADJUSTMENT', 'Opening balance (carried from pre-ledger reward_points)'
FROM app.users u
WHERE u.reward_points <> 0
  AND NOT EXISTS (
    SELECT 1 FROM app.reward_point_transaction t WHERE t.member_id = u.id
  );

-- Re-derive the cache from the ledger for everyone, so the column and the
-- ledger agree from here on.
UPDATE app.users u
SET reward_points = greatest(0, coalesce((
      SELECT sum(t.points)
      FROM app.reward_point_transaction t
      WHERE t.member_id = u.id
    ), 0));
