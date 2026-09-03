-- 0008 · Receipt image on app.wallet_card
--
-- Privilege-plan activation collects a transfer-receipt photo at checkout. It
-- is resized to a small JPEG data URI (like app.prescription.image) and stored
-- here so a Super Admin can see it on the Activations review screen alongside
-- the reference and file name.

ALTER TABLE app.wallet_card
  ADD COLUMN IF NOT EXISTS receipt_image text;
