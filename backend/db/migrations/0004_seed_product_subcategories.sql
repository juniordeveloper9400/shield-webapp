-- ============================================================================
--  0004 · Seed app.product_subcategory to match the app's category browser
-- ============================================================================
--  The customer app (shield agent_invester) and the console both show the same
--  six storefront categories, each split into sub-categories — Personal Care →
--  Skin Care / Hair Care / …  Those sub-categories lived only in the Flutter
--  `CategoryCatalogue` until now; this migration writes them into
--  app.product_subcategory so the admin's "Add product" form can file a product
--  under one, and the app can list by it exactly rather than guessing from the
--  product name.
--
--  The labels here must stay word-for-word identical to
--  lib/module/categories/category_catalogue.dart — the app matches on the
--  label text.
--
--  Idempotent — safe to run more than once:
--    dart run backend/db/apply_migration.dart backend/db/migrations/0004_seed_product_subcategories.sql --yes
-- ============================================================================

SET search_path TO app, public;

-- One sub-category label per category, case-insensitively — lets the seed below
-- use ON CONFLICT and makes a re-run a no-op.
CREATE UNIQUE INDEX IF NOT EXISTS product_subcategory_cat_label_idx
    ON app.product_subcategory (category_id, lower(label));

INSERT INTO app.product_subcategory (category_id, label, sort)
SELECT c.id, v.label, v.sort
FROM (VALUES
    ('personal-care',        'Skin Care',             0),
    ('personal-care',        'Hair Care',             1),
    ('personal-care',        'Oral Care',             2),
    ('personal-care',        'Bath & Body',           3),
    ('personal-care',        'Men Grooming',          4),
    ('personal-care',        'Feminine Care',         5),

    ('health-conditions',    'Bone and Joint Care',   0),
    ('health-conditions',    'Digestive Care',        1),
    ('health-conditions',    'Eye Care',              2),
    ('health-conditions',    'Pain Relief',           3),
    ('health-conditions',    'Smoking Cessation',     4),
    ('health-conditions',    'Liver Care',            5),

    ('vitamins-supplements', 'Multivitamins',         0),
    ('vitamins-supplements', 'Vitamin D',             1),
    ('vitamins-supplements', 'Protein Powder',        2),
    ('vitamins-supplements', 'Omega & Fish Oil',      3),
    ('vitamins-supplements', 'Calcium',               4),
    ('vitamins-supplements', 'Immunity',              5),

    ('diabetes-care',        'Glucometers',           0),
    ('diabetes-care',        'Test Strips',           1),
    ('diabetes-care',        'Sugar Substitutes',     2),
    ('diabetes-care',        'Diabetic Food',         3),
    ('diabetes-care',        'Foot Care',             4),
    ('diabetes-care',        'Insulin Support',       5),

    ('surgicals',            'Gloves & Masks',        0),
    ('surgicals',            'Bandages & Dressings',  1),
    ('surgicals',            'Syringes & Needles',    2),
    ('surgicals',            'Supports & Braces',     3),
    ('surgicals',            'First Aid Kits',        4),
    ('surgicals',            'Mobility Aids',         5),

    ('lab-tests',            'Full Body Checkup',     0),
    ('lab-tests',            'Blood Tests',           1),
    ('lab-tests',            'Thyroid Profile',       2),
    ('lab-tests',            'Vitamin Tests',         3)
) AS v(cat_slug, label, sort)
JOIN app.product_category c ON c.slug = v.cat_slug
ON CONFLICT (category_id, lower(label)) DO NOTHING;
