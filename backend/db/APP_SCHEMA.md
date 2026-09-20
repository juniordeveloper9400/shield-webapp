# Sahakar 360 customer-app schema — `app`

Everything the Flutter app (`lib/module/*`) needs to persist, as one self-contained
Postgres schema named **`app`**, separate from the Prisma-managed `public` schema.

- **DDL:** [`app_schema.sql`](app_schema.sql) — 52 tables, 24 enums, an `updated_at` trigger on every table that has the column.
- **Apply:** `dart run backend/db/apply_app_schema.dart --yes` — runs `DROP SCHEMA IF EXISTS app CASCADE` then the DDL. Touches nothing in `public`.
- **Seed:** `dart run backend/db/seed_app.dart --yes` — loads the reference/content data the app currently hard-codes (stores, tiers, ladder, payment methods, categories, sample lab packages / clinics / dietitians / articles / promos).

## Why a dedicated schema

The 78 tables in `public` are Prisma-managed and shared with a separate Sahakar 360
backend/admin system. Nothing here references them, and "drop the app's tables"
is a single safe statement (`DROP SCHEMA app CASCADE`) that cannot reach
`public`, its RBAC tables, or `_prisma_migrations`.

## Conventions

| | |
|---|---|
| Primary keys | `bigint GENERATED ALWAYS AS IDENTITY` |
| External id | `uuid NOT NULL DEFAULT gen_random_uuid()` on rows an API hands out |
| Money | `numeric(12,2)`, whole rupees |
| Timestamps | `created_at` / `updated_at timestamptz DEFAULT now()`; `updated_at` moved by trigger |
| Soft delete | `deleted_at timestamptz` on `users`, `member_address`, `patient`, `prescription` |
| Closed sets | Postgres enums under `app.` (`app.order_status`, `app.agent_level`, …) |

## Module → table map

| App module (`lib/module/…`) | Tables |
|---|---|
| `auth`, `registration`, `account` | `users` (identity = phone), `reward_point_transaction` |
| `location` | `member_address` |
| `patients` | `patient` |
| `registration/shield_store` | `shield_store` |
| `home`, `health`, `product`, `categories`, `search` | `home_banner`, `promo`, `health_article` (+ `_section`), `customer_review`, `product_category` (+ `_subcategory`), `product` (+ `product_detail`, `product_faq`) |
| `cart` | `cart`, `cart_line` |
| `checkout`, `orders` | `order`, `order_line`, `order_track_step`, `order_receipt`, `payment_method` |
| `prescription` | `prescription`, `prescription_medicine`, `prescription_order` |
| `approvals` | `approval`, `approval_item` |
| `wallet`, `privilege` | `wallet`, `wallet_card`, `wallet_entry`, `membership_tier`, `membership_tier_load` |
| `rewards`, `refer`, `earnings` | `reward_point_transaction`, `referral`, `referral_level` (earnings are derived from `order` + `wallet_card`) |
| `labtest` | `lab_package`, `lab_profile`, `lab_booking`, `lab_booking_patient` |
| `appointment`, `dietitian` | `clinic`, `clinic_doctor`, `dietitian`, `appointment` |
| `investment` | `investment_plan_point` (static pitch content) |
| `agent` (field-sales MLM) | `agent` (self-referencing tree), `agent_customer`, `agent_customer_plan`, `agent_withdrawal`, `agent_wallet_transfer` |
| `investor` | `investor`, `investor_plan_change_request` |
| push / notifications | `device_push_token`, `notification` |

## Notable modelling choices

- **`users`** is the hub, keyed by `phone` (unique). `firebase_uid` links the
  Firebase phone-auth identity. `home_store_id` is the assigned branch;
  `referral_code` / `referred_by_member_id` carry the invite graph.
- **`agent`** and **`investor`** are personas resolved by phone in the app
  today; each has an optional `member_id` so a signed-in member can *be* an
  agent/investor. `agent.parent_id` self-references for the 7-level hierarchy
  (`app.agent_level` enum: `NATIONAL … WARD`).
- **Wallet vs. privilege:** a `wallet` is opened by a `wallet_card` (a
  `PrivilegeLoad`). `wallet_card.amount` is the load, `bonus` the 10%,
  `expires_on` is issue + `membership_tier.validity_months`. `wallet_entry` is
  the signed ledger (`ACTIVATION`, `BONUS`, `TOPUP`, `SPEND`,
  `POINTS_REDEEMED`, `AGENT_EARNINGS`).
- **`order`** carries both `mrp_total` and `paid_total` so "your earnings" (the
  gap) is never a stored number. `billed_wallet_card_id` records which plan a
  member billed an order to.
- **`prescription`** splits member-owned fields (patient, supply duration,
  recurrence) from pharmacy-owned ones (`doctor`, `prescription_medicine` rows
  with `dose_morning/afternoon/night`). `status` walks
  `AWAITING_REVIEW → READ → IN_CART → ORDERED`.
- Forward-declared FKs (`member_address.patient_id`, `cart_line.prescription_id`,
  `order.billed_wallet_card_id`, `wallet_card.sold_by_agent_id`) are added with
  `ALTER TABLE` after both tables exist.

## What the seed does NOT cover

The full product / lab / health-article catalogues live in Dart files that
import Flutter (`IconData`, `Color`) and can't be read from a plain `dart run`.
`seed_app.dart` loads the flutter-free reference data in full and a small
representative sample of the rest — extend it, or import the real catalogues
through the admin tool.
