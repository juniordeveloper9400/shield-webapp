-- ============================================================================
--  0009 · Karinkallathani branch — precise coordinates
-- ============================================================================
--  SHD-KKT was seeded with approximate town-centre coordinates. This sets the
--  branch's real location (Karayil Complex, Karinkallathani), taken from its
--  Google Maps place pin, so distance ranking and the branch map are exact.
--
--  Idempotent — safe to run more than once:
--    dart run backend/db/apply_migration.dart <this file> --yes
-- ============================================================================

SET search_path TO app, public;

UPDATE app.shield_store
   SET latitude = 10.953937, longitude = 76.320280, updated_at = now()
 WHERE code = 'SHD-KKT';
