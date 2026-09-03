-- 0006 · Coordinates on app.shield_store
--
-- Registration and privilege-plan activation ask for the member's location and
-- rank the branches by real distance (haversine) so the nearest one is
-- pre-selected. When a branch has no coordinates the app falls back to the
-- old pincode-prefix ranking, so this is safe to roll out one branch at a time.

ALTER TABLE app.shield_store
  ADD COLUMN IF NOT EXISTS latitude  numeric(9,6),
  ADD COLUMN IF NOT EXISTS longitude numeric(9,6);

-- Approximate town-centre coordinates — good enough to rank branches that are
-- 5–40 km apart. Replace with the exact Maps-pin values when available.
UPDATE app.shield_store SET latitude = v.lat, longitude = v.lng
FROM (VALUES
  ('SHD-MEL', 10.988000, 76.216000),  -- Melattur
  ('SHD-MKP', 10.944000, 76.101000),  -- Makkaraparamba
  ('SHD-TIR', 10.913800, 75.921800),  -- Tirur
  ('SHD-KKT', 10.953937, 76.320280),  -- Karinkallathani
  ('SHD-MJR', 11.120000, 76.119000),  -- Manjeri
  ('SHD-ALN', 10.976000, 76.523000),  -- Alanallur
  ('SHD-TRD', 11.042000, 75.928000),  -- Tirurangadi
  ('SHD-KNP', 10.993000, 76.080000),  -- Kunnumpuram
  ('SHD-KND', 11.139000, 75.964000),  -- Kondotty
  ('SHD-ARK', 11.205000, 76.008000)   -- Areekode
) AS v(code, lat, lng)
WHERE app.shield_store.code = v.code;
