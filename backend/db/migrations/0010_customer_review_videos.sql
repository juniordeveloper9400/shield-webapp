-- ============================================================================
--  0010 · Customer review videos, admin-managed
-- ============================================================================
--  "What our customers have to say" on the home feed moves from a bundled
--  list of asset video files to app.customer_review_video: the pharmacy admin
--  adds, edits, reorders and retires clips from the console, and the app /
--  web build read the active ones straight off this table.
--
--  Seeded with the clips already shipping (their existing bundled asset
--  paths as video_url), so nothing changes on the home feed until an admin
--  actually touches this table — they can then edit, deactivate or replace
--  any of them with a hosted video URL.
--
--  Idempotent — safe to run more than once:
--    dart run backend/db/apply_migration.dart <this file> --yes
-- ============================================================================

SET search_path TO app, public;

CREATE TABLE IF NOT EXISTS app.customer_review_video (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid         uuid NOT NULL DEFAULT gen_random_uuid(),
    name         text NOT NULL,
    subtitle     text NOT NULL DEFAULT '',
    -- A bundled asset path (assets/reviews/…mp4, played from the app bundle)
    -- for the seeded clips, or an http(s) URL to a hosted video for anything
    -- an admin adds afterwards.
    video_url    text NOT NULL,
    -- Optional poster frame — a data: URI (uploaded in the console) or an
    -- http(s) URL. Null for the seeded clips: the app decodes its own poster
    -- frame from the asset.
    thumbnail    text,
    is_active    boolean NOT NULL DEFAULT true,
    sort         integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS customer_review_video_sort_idx
  ON app.customer_review_video(sort);

INSERT INTO app.customer_review_video (name, subtitle, video_url, sort)
SELECT v.name, v.subtitle, v.video_url, v.sort
FROM (VALUES
  ('Melattur',            '', 'assets/reviews/melattur_store.mp4',            0),
  ('Makkaraparamba',      '', 'assets/reviews/makkaraparamba_store.mp4',      1),
  ('Tirur',               '', 'assets/reviews/tirur_store.mp4',               2),
  ('Tirurangadi',         '', 'assets/reviews/tirurangadi_store.mp4',         3),
  ('From the heart',      '', 'assets/reviews/customer_review_from_heart.mp4', 4),
  ('Smart clinic',        '', 'assets/reviews/smart_clinic.mp4',              5),
  ('Preventive health',   '', 'assets/reviews/preventive_health.mp4',         6),
  ('The serum secret',    '', 'assets/reviews/the_serum_secret.mp4',          7)
) AS v(name, subtitle, video_url, sort)
WHERE NOT EXISTS (
  SELECT 1 FROM app.customer_review_video existing
  WHERE existing.video_url = v.video_url
);
