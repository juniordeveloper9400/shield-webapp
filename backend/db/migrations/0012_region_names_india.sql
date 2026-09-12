-- ============================================================================
--  0012 · Rename the six regions to "<Direction> India"
-- ============================================================================
--  app.region (seeded by migration 0015 in the main repo / 0011's sibling
--  here) originally read North / South / East / West / Central / Northeast.
--  Renamed to North India / South India / East India / West India /
--  Central India / Northeast India for clarity in the agent hierarchy
--  (registration screen, "My Team", the admin's Agent approvals position
--  picker) — the app and console both read this name live off app.region, so
--  this is a pure data change: no schema, no code.
--
--  `code` (N/S/E/W/C/NE) and every state's `region_id` are untouched.
--
--  Idempotent — matches by the OLD name, so a re-run after the rename has
--  already happened simply updates nothing:
--    dart run backend/db/apply_migration.dart backend/db/migrations/0012_region_names_india.sql --yes
-- ============================================================================

SET search_path TO app, public;

UPDATE app.region SET name = 'North India'     WHERE name = 'North';
UPDATE app.region SET name = 'South India'     WHERE name = 'South';
UPDATE app.region SET name = 'East India'      WHERE name = 'East';
UPDATE app.region SET name = 'West India'      WHERE name = 'West';
UPDATE app.region SET name = 'Central India'   WHERE name = 'Central';
UPDATE app.region SET name = 'Northeast India' WHERE name = 'Northeast';
