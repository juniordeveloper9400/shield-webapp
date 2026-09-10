-- ============================================================================
--  SHIELD customer app — database schema
-- ============================================================================
--  Everything the Flutter app in lib/module/* needs to persist, as one
--  self-contained Postgres schema named "app".
--
--  Why a dedicated schema and not public:
--    * The existing 78 tables in public are Prisma-managed and shared with a
--      separate SHIELD backend/admin system. Nothing here touches them.
--    * "Drop the app's tables" is then a single safe statement:
--        DROP SCHEMA IF EXISTS app CASCADE;
--      run by apply_app_schema.dart before it recreates everything below.
--
--  Conventions
--    * bigint identity primary keys; a uuid external id on every row that the
--      app or an API would hand out, matching the public-schema convention.
--    * money is numeric(12,2) in whole rupees (the app deals in rupees, and
--      the cart carries paise-free doubles).
--    * created_at / updated_at are timestamptz default now(); updated_at is
--      moved by the trigger at the foot of this file.
--    * deleted_at (nullable) marks a soft delete where the app supports one
--      (addresses, patients, prescriptions).
--    * enum-like closed sets are Postgres enums under the app schema.
--
--  Apply:  dart run backend/db/apply_app_schema.dart --yes
--  Seed :  dart run backend/db/seed_app.dart --yes
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS app;
SET search_path TO app, public;

-- Trigram index on product name for search; harmless if already present.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ---------------------------------------------------------------------------
--  Enums
-- ---------------------------------------------------------------------------
CREATE TYPE app.gender             AS ENUM ('FEMALE', 'MALE', 'OTHER');
CREATE TYPE app.address_label      AS ENUM ('HOME', 'WORK', 'OTHER');
CREATE TYPE app.patient_relation   AS ENUM ('SELF', 'SPOUSE', 'CHILD', 'PARENT', 'OTHER');

CREATE TYPE app.cart_line_source   AS ENUM ('SHOP', 'PRESCRIPTION');

CREATE TYPE app.order_kind         AS ENUM ('STANDARD', 'PRESCRIPTION');
CREATE TYPE app.order_status       AS ENUM ('PROCESSING', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED');
CREATE TYPE app.track_state        AS ENUM ('DONE', 'CURRENT', 'UPCOMING');

CREATE TYPE app.medicine_duration  AS ENUM ('ONE_WEEK', 'FIFTEEN_DAYS', 'ONE_MONTH', 'TWO_MONTHS', 'THREE_MONTHS');
CREATE TYPE app.prescription_status AS ENUM ('AWAITING_REVIEW', 'READ', 'IN_CART', 'ORDERED');
CREATE TYPE app.approval_status    AS ENUM ('PENDING', 'APPROVED', 'PARTIALLY_APPROVED', 'REJECTED', 'CANCELLED');

CREATE TYPE app.privilege_card_kind AS ENUM ('SILVER', 'GOLD', 'PLATINUM');
CREATE TYPE app.wallet_entry_kind  AS ENUM ('ACTIVATION', 'BONUS', 'TOPUP', 'SPEND', 'POINTS_REDEEMED', 'AGENT_EARNINGS');

CREATE TYPE app.reward_txn_reason  AS ENUM ('REGISTRATION', 'REFERRAL_LEVEL', 'ORDER', 'REDEMPTION', 'ADJUSTMENT');
CREATE TYPE app.referral_status    AS ENUM ('SHARED', 'REGISTERED', 'TRANSACTED', 'PLAN_ACTIVATED');

CREATE TYPE app.appointment_kind   AS ENUM ('CLINIC', 'TELE', 'DENTAL', 'DIETITIAN');
CREATE TYPE app.appointment_status AS ENUM ('REQUESTED', 'CONFIRMED', 'COMPLETED', 'CANCELLED');
CREATE TYPE app.lab_booking_status AS ENUM ('REQUESTED', 'CONFIRMED', 'SAMPLE_COLLECTED', 'REPORT_READY', 'CANCELLED');

CREATE TYPE app.agent_level        AS ENUM ('NATIONAL', 'REGION', 'STATE', 'DISTRICT', 'ASSEMBLY', 'LSGD', 'WARD');
CREATE TYPE app.agent_approval     AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
CREATE TYPE app.withdrawal_status  AS ENUM ('PENDING', 'PAID', 'REJECTED');

CREATE TYPE app.investor_plan_type AS ENUM ('YEARLY', 'MONTHLY');
CREATE TYPE app.plan_change_status AS ENUM ('REQUESTED', 'APPROVED', 'REJECTED');

CREATE TYPE app.notification_status AS ENUM ('QUEUED', 'SENT', 'READ');
CREATE TYPE app.push_platform      AS ENUM ('ANDROID', 'IOS', 'WEB');

-- ===========================================================================
--  1 · Reference & content  (seeded by seed_app.dart; edited by admins)
-- ===========================================================================

-- SHIELD outlets — every member is assigned one; orders dispatch from it.
CREATE TABLE app.shield_store (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid         uuid NOT NULL DEFAULT gen_random_uuid(),
    code         text NOT NULL UNIQUE,                 -- 'SHD-MEL'
    name         text NOT NULL,
    area         text NOT NULL,
    city         text NOT NULL,
    state        text NOT NULL,
    pincode      text NOT NULL,
    phone        text NOT NULL DEFAULT '',
    hours        text NOT NULL DEFAULT '8:00 AM – 10:00 PM',
    is_active    boolean NOT NULL DEFAULT true,
    sort         integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

-- Privilege programme tiers: Silver / Gold / Platinum.
CREATE TABLE app.membership_tier (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid             uuid NOT NULL DEFAULT gen_random_uuid(),
    kind             app.privilege_card_kind NOT NULL UNIQUE,
    name             text NOT NULL,                    -- 'Silver Shield'
    bin              text NOT NULL,                    -- first 4 digits of the card no.
    blurb            text NOT NULL DEFAULT '',
    bonus_rate       numeric(4,3) NOT NULL DEFAULT 0.100,
    validity_months  integer NOT NULL DEFAULT 12,
    sort             integer NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

-- The fixed loadable amounts each tier is issued for (Silver: 10k/20k/30k …).
CREATE TABLE app.membership_tier_load (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tier_id     bigint NOT NULL REFERENCES app.membership_tier(id) ON DELETE CASCADE,
    amount      numeric(12,2) NOT NULL,
    sort        integer NOT NULL DEFAULT 0,
    UNIQUE (tier_id, amount)
);

-- Refer-and-earn ladder: 5 rungs, Starter → Legend.
CREATE TABLE app.referral_level (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    level               integer NOT NULL UNIQUE,
    name                text NOT NULL,
    referrals_required  integer NOT NULL,
    points              integer NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- Checkout payment methods.
CREATE TABLE app.payment_method (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        text NOT NULL UNIQUE,                  -- 'upi', 'wallet', 'cod'
    name        text NOT NULL,
    blurb       text NOT NULL DEFAULT '',
    is_live     boolean NOT NULL DEFAULT false,
    sort        integer NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Storefront category groups (tabs on the categories screen).
CREATE TABLE app.product_category (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid         uuid NOT NULL DEFAULT gen_random_uuid(),
    slug         text NOT NULL UNIQUE,
    title        text NOT NULL,
    tab_label    text NOT NULL,
    icon_name    text,
    image        text,
    banner_image text,
    panel_tint   text,
    offer        text NOT NULL DEFAULT '',
    sort         integer NOT NULL DEFAULT 0,
    is_active    boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.product_subcategory (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id  bigint NOT NULL REFERENCES app.product_category(id) ON DELETE CASCADE,
    label        text NOT NULL,
    icon_name    text,
    image        text,
    offer        text NOT NULL DEFAULT '',
    sort         integer NOT NULL DEFAULT 0
);

-- Catalogue products (storefront + pharmacy shelf).
CREATE TABLE app.product (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid            uuid NOT NULL DEFAULT gen_random_uuid(),
    code            text UNIQUE,
    name            text NOT NULL,
    pack            text NOT NULL DEFAULT '',
    brand           text,
    category_id     bigint REFERENCES app.product_category(id) ON DELETE SET NULL,
    subcategory_id  bigint REFERENCES app.product_subcategory(id) ON DELETE SET NULL,
    price           numeric(12,2) NOT NULL DEFAULT 0,
    mrp             numeric(12,2) NOT NULL DEFAULT 0,
    discount_label  text,
    icon_name       text,
    image           text,
    is_prescription_only boolean NOT NULL DEFAULT false,
    status          text NOT NULL DEFAULT 'ACTIVE',
    stock_quantity  numeric(12,2) NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX product_category_idx ON app.product(category_id);
CREATE INDEX product_name_trgm    ON app.product USING gin (lower(name) gin_trgm_ops);

-- Rich product-detail page content (1:1 with product).
CREATE TABLE app.product_detail (
    product_id    bigint PRIMARY KEY REFERENCES app.product(id) ON DELETE CASCADE,
    form          text,                                -- tablet / syrup / …
    manufacturer  text,
    description    text NOT NULL DEFAULT '',
    ingredients    text NOT NULL DEFAULT '',
    storage        text NOT NULL DEFAULT '',
    highlights     text[] NOT NULL DEFAULT '{}',
    benefits       text[] NOT NULL DEFAULT '{}',
    directions     text[] NOT NULL DEFAULT '{}',
    safety         text[] NOT NULL DEFAULT '{}',
    updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.product_faq (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  bigint NOT NULL REFERENCES app.product(id) ON DELETE CASCADE,
    question    text NOT NULL,
    answer      text NOT NULL,
    sort        integer NOT NULL DEFAULT 0
);

-- Lab-test packages and the profiles inside them.
CREATE TABLE app.lab_package (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid           uuid NOT NULL DEFAULT gen_random_uuid(),
    slug           text NOT NULL UNIQUE,
    name           text NOT NULL,
    test_count     integer NOT NULL DEFAULT 0,
    profile_count  integer NOT NULL DEFAULT 0,
    rating         text,
    booked         text,
    report_in      text,
    price          numeric(12,2) NOT NULL DEFAULT 0,
    mrp            numeric(12,2) NOT NULL DEFAULT 0,
    saved          numeric(12,2) NOT NULL DEFAULT 0,
    inherits_from  text,
    inherits_summary text,
    extras_label   text,
    for_whom       text,
    age_range      text,
    preparation    text,
    sample         text,
    organs         text[] NOT NULL DEFAULT '{}',
    about          text NOT NULL DEFAULT '',
    is_active      boolean NOT NULL DEFAULT true,
    sort           integer NOT NULL DEFAULT 0,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.lab_profile (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lab_package_id  bigint NOT NULL REFERENCES app.lab_package(id) ON DELETE CASCADE,
    emoji           text NOT NULL DEFAULT '',
    name            text NOT NULL,
    parameters      integer NOT NULL DEFAULT 0,
    is_extra        boolean NOT NULL DEFAULT false,
    sort            integer NOT NULL DEFAULT 0
);

-- Partner clinics for the appointments screen.
CREATE TABLE app.clinic (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid          uuid NOT NULL DEFAULT gen_random_uuid(),
    name          text NOT NULL,
    type          text,
    location      text,
    phone         text,
    description   text NOT NULL DEFAULT '',
    tint          text,
    is_verified   boolean NOT NULL DEFAULT false,
    specialities  text[] NOT NULL DEFAULT '{}',
    is_active     boolean NOT NULL DEFAULT true,
    sort          integer NOT NULL DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.clinic_doctor (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    clinic_id   bigint NOT NULL REFERENCES app.clinic(id) ON DELETE CASCADE,
    name        text NOT NULL,
    speciality  text,
    fee         text,
    sort        integer NOT NULL DEFAULT 0
);

CREATE TABLE app.dietitian (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid             uuid NOT NULL DEFAULT gen_random_uuid(),
    name             text NOT NULL,
    qualification    text,
    focus            text[] NOT NULL DEFAULT '{}',
    experience_years integer NOT NULL DEFAULT 0,
    languages        text[] NOT NULL DEFAULT '{}',
    fee              numeric(12,2) NOT NULL DEFAULT 0,
    next_slot        text,
    is_active        boolean NOT NULL DEFAULT true,
    sort             integer NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Home-feed editorial: health articles, promo cards, video reviews, banners.
CREATE TABLE app.health_article (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid         uuid NOT NULL DEFAULT gen_random_uuid(),
    slug         text NOT NULL UNIQUE,
    title        text NOT NULL,
    topics       text[] NOT NULL DEFAULT '{}',
    author       text,
    published_on date,
    hero_kicker  text,
    intro        text[] NOT NULL DEFAULT '{}',
    icon_name    text,
    tint         text,
    is_published boolean NOT NULL DEFAULT true,
    sort         integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.health_article_section (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    article_id  bigint NOT NULL REFERENCES app.health_article(id) ON DELETE CASCADE,
    sort        integer NOT NULL DEFAULT 0,
    heading     text NOT NULL,
    paragraphs  text[] NOT NULL DEFAULT '{}'
);

CREATE TABLE app.promo (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title_top    text,
    title_middle text,
    title_accent text,
    title_tail   text,
    cta          text,
    code         text,
    percent      text,
    background   text,
    starts_on    date,
    ends_on      date,
    is_active    boolean NOT NULL DEFAULT true,
    sort         integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.customer_review (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid             uuid NOT NULL DEFAULT gen_random_uuid(),
    name             text NOT NULL,
    subtitle         text,
    video_url        text,
    duration_seconds integer,
    is_active        boolean NOT NULL DEFAULT true,
    sort             integer NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.home_banner (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title       text,
    subtitle    text,
    image       text,
    cta         text,
    target      text,                                 -- deep-link / route
    is_active   boolean NOT NULL DEFAULT true,
    sort        integer NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Static content for the investment-plan pitch screen.
CREATE TABLE app.investment_plan_point (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind   text NOT NULL DEFAULT 'PLAN',              -- 'HIGHLIGHT' | 'PLAN'
    title  text NOT NULL,
    body   text NOT NULL DEFAULT '',
    icon_name text,
    sort   integer NOT NULL DEFAULT 0
);

-- ===========================================================================
--  2 · Users & profile
-- ===========================================================================

-- The account. Identity is the mobile number (Firebase phone auth).
CREATE TABLE app.users (
    id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid                    uuid NOT NULL DEFAULT gen_random_uuid(),
    phone                   text NOT NULL UNIQUE,          -- 10 digits, no +91
    name                    text NOT NULL,
    firebase_uid            text UNIQUE,
    email                   text,
    gender                  app.gender,
    dob                     date,
    address                 text,
    place                   text,
    pincode                 text,
    state                   text,
    home_store_id           bigint REFERENCES app.shield_store(id) ON DELETE SET NULL,
    reward_points           integer NOT NULL DEFAULT 0,
    referral_code           text UNIQUE,                   -- this member's own invite code
    referred_by_member_id   bigint REFERENCES app.users(id) ON DELETE SET NULL,
    registration_completed_at timestamptz,
    registration_prompt_dismissed boolean NOT NULL DEFAULT false,
    last_login_at           timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    deleted_at              timestamptz
);

-- Delivery addresses. label + names + phone are per-address (gift/other person).
CREATE TABLE app.member_address (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid         uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id    bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    label        app.address_label NOT NULL DEFAULT 'HOME',
    house        text NOT NULL,
    area         text NOT NULL,
    landmark     text NOT NULL DEFAULT '',
    pincode      text NOT NULL,
    city         text,
    state        text,
    first_name   text NOT NULL DEFAULT '',
    last_name    text NOT NULL DEFAULT '',
    phone        text NOT NULL DEFAULT '',
    patient_id   bigint,                                   -- FK added after app.patient
    is_default   boolean NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    deleted_at   timestamptz
);
CREATE INDEX member_address_member_idx ON app.member_address(member_id) WHERE deleted_at IS NULL;

-- People a member orders medicine for (self, family, others).
CREATE TABLE app.patient (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid        uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id   bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    name        text NOT NULL,
    phone       text NOT NULL DEFAULT '',
    address     text NOT NULL DEFAULT '',
    dob         date NOT NULL,
    gender      app.gender NOT NULL DEFAULT 'OTHER',
    abha_id     text NOT NULL DEFAULT '',
    relation    app.patient_relation NOT NULL DEFAULT 'SELF',
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    deleted_at  timestamptz
);
CREATE INDEX patient_member_idx ON app.patient(member_id) WHERE deleted_at IS NULL;

ALTER TABLE app.member_address
    ADD CONSTRAINT member_address_patient_fk
    FOREIGN KEY (patient_id) REFERENCES app.patient(id) ON DELETE SET NULL;

-- FCM/APNs tokens for push.
CREATE TABLE app.device_push_token (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid        uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id   bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    token       text NOT NULL,
    platform    app.push_platform NOT NULL,
    device_label text,
    is_active   boolean NOT NULL DEFAULT true,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (token)
);

CREATE TABLE app.notification (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid        uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id   bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    title       text NOT NULL,
    body        text NOT NULL DEFAULT '',
    channel     text NOT NULL DEFAULT 'PUSH',
    status      app.notification_status NOT NULL DEFAULT 'QUEUED',
    deep_link   text,
    sent_at     timestamptz,
    read_at     timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notification_member_idx ON app.notification(member_id, created_at DESC);

-- ===========================================================================
--  3 · Cart & orders
-- ===========================================================================

-- One live cart per member.
CREATE TABLE app.cart (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    member_id   bigint NOT NULL UNIQUE REFERENCES app.users(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.cart_line (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cart_id     bigint NOT NULL REFERENCES app.cart(id) ON DELETE CASCADE,
    product_id  bigint REFERENCES app.product(id) ON DELETE SET NULL,
    name        text NOT NULL,
    pack        text NOT NULL DEFAULT '',
    price       numeric(12,2) NOT NULL DEFAULT 0,        -- 0 = pharmacist prices later
    mrp         numeric(12,2) NOT NULL DEFAULT 0,
    image       text,
    qty         integer NOT NULL DEFAULT 1 CHECK (qty >= 1 AND qty <= 999),
    source      app.cart_line_source NOT NULL DEFAULT 'SHOP',
    prescription_id bigint,                              -- FK added after app.prescription
    added_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX cart_line_cart_idx ON app.cart_line(cart_id);

-- A placed order (standard checkout or a prescription order).
CREATE TABLE app."order" (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid                uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id           bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    code                text NOT NULL UNIQUE,             -- 'SH-100423'
    kind                app.order_kind NOT NULL DEFAULT 'STANDARD',
    status              app.order_status NOT NULL DEFAULT 'PROCESSING',
    item_count          integer NOT NULL DEFAULT 0,
    mrp_total           numeric(12,2) NOT NULL DEFAULT 0,
    paid_total          numeric(12,2) NOT NULL DEFAULT 0,
    delivery_fee        numeric(12,2) NOT NULL DEFAULT 0,
    delivery_address_id bigint REFERENCES app.member_address(id) ON DELETE SET NULL,
    store_id            bigint REFERENCES app.shield_store(id) ON DELETE SET NULL,
    payment_method_id   bigint REFERENCES app.payment_method(id) ON DELETE SET NULL,
    billed_wallet_card_id bigint,                         -- FK added after app.wallet_card
    reference           text,                             -- UPI ref / notes
    placed_on           date NOT NULL DEFAULT current_date,
    placed_at           timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX order_member_idx ON app."order"(member_id, placed_at DESC);

CREATE TABLE app.order_line (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES app."order"(id) ON DELETE CASCADE,
    product_id  bigint REFERENCES app.product(id) ON DELETE SET NULL,
    name        text NOT NULL,
    pack        text NOT NULL DEFAULT '',
    unit_price  numeric(12,2) NOT NULL DEFAULT 0,
    mrp         numeric(12,2) NOT NULL DEFAULT 0,
    qty         integer NOT NULL DEFAULT 1
);
CREATE INDEX order_line_order_idx ON app.order_line(order_id);

CREATE TABLE app.order_track_step (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES app."order"(id) ON DELETE CASCADE,
    sort        integer NOT NULL DEFAULT 0,
    title       text NOT NULL,
    detail      text,
    state       app.track_state NOT NULL DEFAULT 'UPCOMING',
    occurred_at timestamptz
);

-- Uploaded payment receipt for an order (manual UPI/bank transfer flow).
CREATE TABLE app.order_receipt (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid         uuid NOT NULL DEFAULT gen_random_uuid(),
    order_id     bigint NOT NULL REFERENCES app."order"(id) ON DELETE CASCADE,
    payer_name   text,
    reference    text,                                   -- UTR / txn id
    amount       numeric(12,2),
    storage_path text,
    file_name    text,
    mime_type    text,
    uploaded_at  timestamptz NOT NULL DEFAULT now(),
    verified_at  timestamptz
);

-- ===========================================================================
--  4 · Prescriptions & approvals
-- ===========================================================================

CREATE TABLE app.prescription (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid              uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id         bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    patient_id        bigint NOT NULL REFERENCES app.patient(id) ON DELETE RESTRICT,
    -- Branch the script is filled at. Set by the app at upload (registered
    -- store → nearest by pincode → first branch), so a Pharmacy Admin sees it
    -- even when the member never registered a home store.
    store_id          bigint REFERENCES app.shield_store(id) ON DELETE SET NULL,
    code              text NOT NULL UNIQUE,               -- 'RX-0004'
    file_name         text NOT NULL DEFAULT '',
    storage_path      text,
    doctor            text NOT NULL DEFAULT '',           -- read at the counter
    duration          app.medicine_duration,
    custom_days       integer,
    recurring_from    date,
    recurring_until   date,                               -- null = never expires
    status            app.prescription_status NOT NULL DEFAULT 'AWAITING_REVIEW',
    reviewed_at       timestamptz,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    deleted_at        timestamptz
);
CREATE INDEX prescription_member_idx ON app.prescription(member_id) WHERE deleted_at IS NULL;
CREATE INDEX prescription_store_idx  ON app.prescription(store_id);

-- Lines the pharmacy keyed in after reading the file. Dose is morning-afternoon-night.
CREATE TABLE app.prescription_medicine (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    prescription_id  bigint NOT NULL REFERENCES app.prescription(id) ON DELETE CASCADE,
    sort             integer NOT NULL DEFAULT 0,
    name             text NOT NULL,
    pack             text NOT NULL DEFAULT '',
    dose_morning     integer NOT NULL DEFAULT 0,
    dose_afternoon   integer NOT NULL DEFAULT 0,
    dose_night       integer NOT NULL DEFAULT 0,
    product_id       bigint REFERENCES app.product(id) ON DELETE SET NULL
);

-- A prescription submitted for fulfilment (its own status trail before the order).
CREATE TABLE app.prescription_order (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid             uuid NOT NULL DEFAULT gen_random_uuid(),
    prescription_id  bigint NOT NULL REFERENCES app.prescription(id) ON DELETE CASCADE,
    order_id         bigint REFERENCES app."order"(id) ON DELETE SET NULL,
    store_id         bigint REFERENCES app.shield_store(id) ON DELETE SET NULL,
    status           text NOT NULL DEFAULT 'SUBMITTED',
    customer_notes   text,
    submitted_at     timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE app.cart_line
    ADD CONSTRAINT cart_line_prescription_fk
    FOREIGN KEY (prescription_id) REFERENCES app.prescription(id) ON DELETE SET NULL;

-- Pharmacist-raised approval (substitutions / out-of-stock / price confirmation).
CREATE TABLE app.approval (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid             uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id        bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    order_id         bigint REFERENCES app."order"(id) ON DELETE SET NULL,
    prescription_id  bigint REFERENCES app.prescription(id) ON DELETE SET NULL,
    code             text NOT NULL UNIQUE,               -- 'APR-0007'
    order_ref        text,
    patient_name     text,
    pharmacist_note  text NOT NULL DEFAULT '',
    status           app.approval_status NOT NULL DEFAULT 'PENDING',
    raised_on        date NOT NULL DEFAULT current_date,
    responded_at     timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX approval_member_idx ON app.approval(member_id, created_at DESC);

CREATE TABLE app.approval_item (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    approval_id  bigint NOT NULL REFERENCES app.approval(id) ON DELETE CASCADE,
    name         text NOT NULL,
    pack         text NOT NULL DEFAULT '',
    quantity     integer NOT NULL DEFAULT 1,
    price        numeric(12,2) NOT NULL DEFAULT 0,
    note         text NOT NULL DEFAULT '',
    is_accepted  boolean
);

-- ===========================================================================
--  5 · Wallet · privilege · rewards · referrals
-- ===========================================================================

-- One SHIELD wallet per member; opened by activating a privilege card.
CREATE TABLE app.wallet (
    id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    member_id            bigint NOT NULL UNIQUE REFERENCES app.users(id) ON DELETE CASCADE,
    balance              numeric(12,2) NOT NULL DEFAULT 0,
    reward_points        integer NOT NULL DEFAULT 0,
    redeemed_this_month  numeric(12,2) NOT NULL DEFAULT 0,
    opened_at            timestamptz,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);

-- A privilege card on the wallet. amount = load; bonus = 10%; credited = sum.
--
-- A card is submitted from the app as `PENDING` and credits nothing; a Super
-- Admin in the console approves it (→ the ledger lines and the balance move) or
-- rejects it with a note the member sees in the wallet.
CREATE TABLE app.wallet_card (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid           uuid NOT NULL DEFAULT gen_random_uuid(),
    wallet_id      bigint NOT NULL REFERENCES app.wallet(id) ON DELETE CASCADE,
    tier_id        bigint NOT NULL REFERENCES app.membership_tier(id) ON DELETE RESTRICT,
    amount         numeric(12,2) NOT NULL,
    bonus          numeric(12,2) NOT NULL,
    recharged_extra numeric(12,2) NOT NULL DEFAULT 0,
    card_number    text,
    store_id       bigint REFERENCES app.shield_store(id) ON DELETE SET NULL,
    status         app.approval_status NOT NULL DEFAULT 'PENDING',
    submitted_at   timestamptz NOT NULL DEFAULT now(),
    reviewed_at    timestamptz,
    reviewer_note  text NOT NULL DEFAULT '',
    receipt_reference text,                               -- the 'PV-…' ref / bank UTR
    receipt_file_name text,
    issued_on      date NOT NULL DEFAULT current_date,
    recharged_on   date NOT NULL DEFAULT current_date,
    expires_on     date NOT NULL,
    sold_by_agent_id bigint,                              -- FK added after app.agent
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX wallet_card_wallet_idx ON app.wallet_card(wallet_id);
CREATE INDEX wallet_card_status_idx ON app.wallet_card(status, submitted_at DESC);

ALTER TABLE app."order"
    ADD CONSTRAINT order_billed_wallet_card_fk
    FOREIGN KEY (billed_wallet_card_id) REFERENCES app.wallet_card(id) ON DELETE SET NULL;

-- The wallet ledger. amount is signed: credits positive, debits negative.
CREATE TABLE app.wallet_entry (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wallet_id    bigint NOT NULL REFERENCES app.wallet(id) ON DELETE CASCADE,
    kind         app.wallet_entry_kind NOT NULL,
    label        text NOT NULL,
    amount       numeric(12,2) NOT NULL,
    occurred_on  date NOT NULL DEFAULT current_date,
    wallet_card_id bigint REFERENCES app.wallet_card(id) ON DELETE SET NULL,
    order_id     bigint REFERENCES app."order"(id) ON DELETE SET NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX wallet_entry_wallet_idx ON app.wallet_entry(wallet_id, created_at DESC);

-- Reward-point ledger (registration bonus, referral rungs, redemptions).
CREATE TABLE app.reward_point_transaction (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    member_id   bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    points      integer NOT NULL,                        -- signed
    reason      app.reward_txn_reason NOT NULL,
    ref_type    text,
    ref_id      bigint,
    note        text,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reward_point_member_idx ON app.reward_point_transaction(member_id, created_at DESC);

-- One referred person and how far they got.
CREATE TABLE app.referral (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid                uuid NOT NULL DEFAULT gen_random_uuid(),
    inviter_member_id   bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    invitee_member_id   bigint REFERENCES app.users(id) ON DELETE SET NULL,
    invitee_phone       text,
    code_used           text,
    status              app.referral_status NOT NULL DEFAULT 'SHARED',
    plan_amount         numeric(12,2),
    commission_amount   numeric(12,2) NOT NULL DEFAULT 0,  -- "Sahakar money"
    registered_at       timestamptz,
    transacted_at       timestamptz,
    plan_activated_at   timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX referral_inviter_idx ON app.referral(inviter_member_id);

-- ===========================================================================
--  6 · Lab bookings & appointments
-- ===========================================================================

CREATE TABLE app.lab_booking (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid            uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id       bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    lab_package_id  bigint NOT NULL REFERENCES app.lab_package(id) ON DELETE RESTRICT,
    patients_count  integer NOT NULL DEFAULT 1,
    unit_price      numeric(12,2) NOT NULL DEFAULT 0,
    total_price     numeric(12,2) NOT NULL DEFAULT 0,
    status          app.lab_booking_status NOT NULL DEFAULT 'REQUESTED',
    scheduled_for   timestamptz,
    address_id      bigint REFERENCES app.member_address(id) ON DELETE SET NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX lab_booking_member_idx ON app.lab_booking(member_id, created_at DESC);

CREATE TABLE app.lab_booking_patient (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lab_booking_id  bigint NOT NULL REFERENCES app.lab_booking(id) ON DELETE CASCADE,
    patient_id      bigint REFERENCES app.patient(id) ON DELETE SET NULL,
    name            text,
    age             integer
);

CREATE TABLE app.appointment (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid          uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id     bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    kind          app.appointment_kind NOT NULL DEFAULT 'CLINIC',
    clinic_id     bigint REFERENCES app.clinic(id) ON DELETE SET NULL,
    dietitian_id  bigint REFERENCES app.dietitian(id) ON DELETE SET NULL,
    patient_id    bigint REFERENCES app.patient(id) ON DELETE SET NULL,
    doctor_name   text,
    fee           numeric(12,2),
    status        app.appointment_status NOT NULL DEFAULT 'REQUESTED',
    scheduled_for timestamptz,
    remarks       text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX appointment_member_idx ON app.appointment(member_id, created_at DESC);

-- ===========================================================================
--  7 · Agent (field-sales MLM) portal
-- ===========================================================================

CREATE TABLE app.agent (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid             uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id        bigint REFERENCES app.users(id) ON DELETE SET NULL,
    code             text NOT NULL UNIQUE,               -- 'SHD-NAT-001'
    name             text NOT NULL,
    phone            text NOT NULL,
    level            app.agent_level NOT NULL,
    parent_id        bigint REFERENCES app.agent(id) ON DELETE SET NULL,
    active           boolean NOT NULL DEFAULT true,
    area             text NOT NULL DEFAULT '',
    -- KYC (blank on seed agents, filled by the registration flow)
    first_name       text NOT NULL DEFAULT '',
    middle_name      text NOT NULL DEFAULT '',
    last_name        text NOT NULL DEFAULT '',
    dob              date,
    aadhaar          text NOT NULL DEFAULT '',           -- 12 digits, no spaces
    pan              text NOT NULL DEFAULT '',           -- uppercase
    address          text NOT NULL DEFAULT '',
    pincode          text NOT NULL DEFAULT '',
    place            text NOT NULL DEFAULT '',
    account_number   text NOT NULL DEFAULT '',           -- payout bank account
    photo_path       text,
    approval_status  app.agent_approval NOT NULL DEFAULT 'APPROVED',
    -- rolled-up money (whole rupees)
    earned           numeric(12,2) NOT NULL DEFAULT 0,
    redeemed         numeric(12,2) NOT NULL DEFAULT 0,
    personal_sales   numeric(12,2) NOT NULL DEFAULT 0,
    moved_to_wallet  numeric(12,2) NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX agent_parent_idx ON app.agent(parent_id);
CREATE INDEX agent_phone_idx  ON app.agent(phone);

ALTER TABLE app.wallet_card
    ADD CONSTRAINT wallet_card_sold_by_agent_fk
    FOREIGN KEY (sold_by_agent_id) REFERENCES app.agent(id) ON DELETE SET NULL;

-- The agent-registration approval queue (migration 0011). A recruit submitted
-- from the app lands here as PENDING; the admin console approves it into an
-- app.agent row (at a confirmed level/parent/area) or rejects it with a reason.
-- app.agent therefore only ever holds real, approved agents.
CREATE TABLE app.agent_request (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid              uuid NOT NULL DEFAULT gen_random_uuid(),
    parent_agent_id   bigint REFERENCES app.agent(id) ON DELETE SET NULL,
    requested_level   app.agent_level NOT NULL,
    requested_area    text NOT NULL DEFAULT '',
    requested_area_id uuid,
    name              text NOT NULL,
    phone             text NOT NULL,
    first_name        text NOT NULL DEFAULT '',
    middle_name       text NOT NULL DEFAULT '',
    last_name         text NOT NULL DEFAULT '',
    dob               date,
    aadhaar           text NOT NULL DEFAULT '',
    pan               text NOT NULL DEFAULT '',
    address           text NOT NULL DEFAULT '',
    pincode           text NOT NULL DEFAULT '',
    place             text NOT NULL DEFAULT '',
    account_number    text NOT NULL DEFAULT '',
    photo_path        text,
    status            app.agent_approval NOT NULL DEFAULT 'PENDING',
    reviewer_note     text NOT NULL DEFAULT '',
    reviewed_at       timestamptz,
    agent_id          bigint REFERENCES app.agent(id) ON DELETE SET NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX agent_request_status_idx ON app.agent_request(status, created_at DESC);
CREATE INDEX agent_request_phone_idx  ON app.agent_request(phone);
CREATE INDEX agent_request_parent_idx ON app.agent_request(parent_agent_id);

-- A customer an agent personally sold privilege cards to ("Direct sale").
CREATE TABLE app.agent_customer (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid        uuid NOT NULL DEFAULT gen_random_uuid(),
    agent_id    bigint NOT NULL REFERENCES app.agent(id) ON DELETE CASCADE,
    member_id   bigint REFERENCES app.users(id) ON DELETE SET NULL,
    name        text NOT NULL,
    phone       text NOT NULL DEFAULT '',
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX agent_customer_agent_idx ON app.agent_customer(agent_id);

CREATE TABLE app.agent_customer_plan (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    agent_customer_id bigint NOT NULL REFERENCES app.agent_customer(id) ON DELETE CASCADE,
    tier_id           bigint NOT NULL REFERENCES app.membership_tier(id) ON DELETE RESTRICT,
    amount            numeric(12,2) NOT NULL,
    activated_on      date NOT NULL,
    wallet_card_id    bigint REFERENCES app.wallet_card(id) ON DELETE SET NULL
);

CREATE TABLE app.agent_withdrawal (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid         uuid NOT NULL DEFAULT gen_random_uuid(),
    agent_id     bigint NOT NULL REFERENCES app.agent(id) ON DELETE CASCADE,
    amount       numeric(12,2) NOT NULL,
    status       app.withdrawal_status NOT NULL DEFAULT 'PENDING',
    requested_on date NOT NULL DEFAULT current_date,
    processed_on date,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX agent_withdrawal_agent_idx ON app.agent_withdrawal(agent_id, created_at DESC);

-- Commission an agent moved from the payout pot into their SHIELD wallet.
CREATE TABLE app.agent_wallet_transfer (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    agent_id        bigint NOT NULL REFERENCES app.agent(id) ON DELETE CASCADE,
    amount          numeric(12,2) NOT NULL,
    wallet_entry_id bigint REFERENCES app.wallet_entry(id) ON DELETE SET NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- ===========================================================================
--  8 · Investor portal
-- ===========================================================================

CREATE TABLE app.investor (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid             uuid NOT NULL DEFAULT gen_random_uuid(),
    member_id        bigint REFERENCES app.users(id) ON DELETE SET NULL,
    code             text NOT NULL UNIQUE,               -- 'SHD-INV-001'
    name             text NOT NULL,
    phone            text NOT NULL,
    invested_store_id bigint REFERENCES app.shield_store(id) ON DELETE SET NULL,
    total_units      integer NOT NULL DEFAULT 0,
    unit_price       numeric(12,2) NOT NULL DEFAULT 150000,
    invested_since   date NOT NULL,
    roi_percent      numeric(6,2) NOT NULL DEFAULT 0,
    plan_type        app.investor_plan_type NOT NULL DEFAULT 'YEARLY',
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX investor_phone_idx ON app.investor(phone);

CREATE TABLE app.investor_plan_change_request (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    investor_id       bigint NOT NULL REFERENCES app.investor(id) ON DELETE CASCADE,
    requested_plan_type app.investor_plan_type NOT NULL,
    status            app.plan_change_status NOT NULL DEFAULT 'REQUESTED',
    note              text,
    created_at        timestamptz NOT NULL DEFAULT now(),
    resolved_at       timestamptz
);

-- ===========================================================================
--  9 · Admin console (shieldweb/) logins
-- ===========================================================================
--  Also created by backend/db/migrations/0001_admin_user.sql (idempotent) so
--  an existing database can pick it up without a full rebuild.

CREATE TYPE app.admin_role AS ENUM
    ('SUPERADMIN', 'PHARMACY', 'LAB', 'APPOINTMENTS');

-- One row per staff login. Identity is a Firebase Email/Password account; this
-- row says which role it holds and, for a Pharmacy Admin, which branch.
CREATE TABLE app.admin_user (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    uuid          uuid NOT NULL DEFAULT gen_random_uuid(),
    firebase_uid  text UNIQUE,
    email         text NOT NULL UNIQUE,
    name          text NOT NULL,
    role          app.admin_role NOT NULL DEFAULT 'PHARMACY',
    store_id      bigint REFERENCES app.shield_store(id) ON DELETE SET NULL,
    avatar_color  text NOT NULL DEFAULT '#2c57a6',
    is_active     boolean NOT NULL DEFAULT true,
    last_login_at timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ===========================================================================
--  updated_at trigger
-- ===========================================================================
CREATE OR REPLACE FUNCTION app.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DO $$
DECLARE t text;
BEGIN
    FOR t IN
        SELECT table_name FROM information_schema.columns
        WHERE table_schema = 'app' AND column_name = 'updated_at'
    LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON app.%I
               FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at()',
            t || '_touch', t);
    END LOOP;
END;
$$;
