-- 0005 · Home-feed section flags on app.product
--
-- The customer home feed has three product rows — "Popular Items", "Deals You
-- Love" and "Offer of the Day". Until now they were derived (newest = popular,
-- discounted = deal). These flags let a pharmacy admin place a product into a
-- row explicitly from the console; when no product is flagged for a row the
-- app falls back to the old derived behaviour so the row is never empty.

ALTER TABLE app.product
  ADD COLUMN IF NOT EXISTS is_popular      boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_deal         boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_offer_of_day boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS product_home_section_idx
  ON app.product (is_popular, is_deal, is_offer_of_day)
  WHERE is_popular OR is_deal OR is_offer_of_day;
