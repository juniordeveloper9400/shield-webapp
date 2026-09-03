-- ============================================================================
--  0007 · Prescription image + admin-built intake card
-- ============================================================================
--  The prescription flow changes from "app auto-reads the script" to
--  "customer places the fulfilment order, then a pharmacist builds the intake
--  card in the console and sends it back".
--
--  * app.prescription.image        — the uploaded script itself, a resized
--                                    JPEG data URI, so the pharmacy admin can
--                                    read it in shieldweb (same pattern as
--                                    app.product.image / payment receipts).
--  * app.prescription_medicine.total_units
--                                  — the quantity the pharmacist enters per
--                                    line, alongside the morning/afternoon/
--                                    night intake code. No longer derived from
--                                    intake × days; the counter decides it.
--
--  No new prescription_status value: the app tells "order placed, waiting on
--  the pharmacist" from "intake card sent" by whether prescription_medicine
--  rows exist. The console still moves the row AWAITING_REVIEW → ORDERED (order
--  placed) → READ (intake card sent) for its own list.
--
--  Idempotent — safe to run more than once:
--    dart run backend/db/apply_migration.dart backend/db/migrations/0007_prescription_intake_card.sql --yes
-- ============================================================================

SET search_path TO app, public;

ALTER TABLE app.prescription
  ADD COLUMN IF NOT EXISTS image text;

ALTER TABLE app.prescription_medicine
  ADD COLUMN IF NOT EXISTS total_units integer NOT NULL DEFAULT 0;
