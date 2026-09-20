# backend

Backend concerns for the Sahakar 360 app — the Neon Postgres database and the tools
that talk to it. (A separate admin website will live in its own folder later.)

## Database

- **Provider:** Neon (serverless Postgres), region `ap-south-1`
- **Engine:** PostgreSQL 18.6
- **Database / role:** `neondb` / `neondb_owner`
- **Pooled host:** `ep-billowing-star-aozk27aq-pooler.c-2.ap-southeast-1.aws.neon.tech`
- **Data API (PostgREST):** `https://ep-billowing-star-aozk27aq.apirest.c-2.ap-southeast-1.aws.neon.tech/neondb/rest/v1`

The connection string lives in `.env` at the repo root (git-ignored). Copy
`.env.example` and paste the value from the Neon console. The Dart tools in
`backend/db/` read `.env` directly.

**The Flutter app compiles the value in from a git-ignored source file, not
from `--dart-define`.** The URL contains `&`; `flutter.bat` runs under cmd.exe
on Windows, which treats `&` on the command line as a statement separator, so
every `--dart-define=DATABASE_URL=…&…` (and the file variants that expand to it)
arrived truncated or empty and every Neon write no-oped. Instead:

```
dart run tool/gen_neon_secret.dart     # writes lib/data/neon/neon_secret.dart from .env (git-ignored)
flutter run
flutter build apk --release            # or: powershell -File build_apk.ps1
```

Re-run `gen_neon_secret.dart` whenever `.env` changes. `neon_secret.dart` holds
the DB password — it is git-ignored; `neon_secret.example.dart` is the checked-in
template. The app reads it via `NeonHttp` (`lib/data/neon/neon_http.dart`, HTTPS)
for the member writes and `NeonDatabase` (`neon_database.dart`, socket) for the
rest; both fall back to `--dart-define=DATABASE_URL` where the shell is safe.

## Schemas

Two schemas, kept apart on purpose:

### `public` — the admin/back-office system

**Prisma-managed** (`_prisma_migrations`), 78 tables covering customers,
products, purchases, wallets, memberships, prescriptions, agents/commissions,
RBAC (`roles` / `permissions`), auth sessions, documents, and more. Its
migrations live in a separate repo. Nothing in this folder writes to it.

`db/SCHEMA.md` is a generated snapshot of `public`: every table with its
columns, keys and live row count. Regenerate it any time with:

```
dart run backend/db/introspect.dart      # read-only
```

### `app` — the customer Flutter app

A self-contained schema for everything `lib/module/*` persists — 52 tables,
24 enums. Documented in [`db/APP_SCHEMA.md`](db/APP_SCHEMA.md); DDL in
[`db/app_schema.sql`](db/app_schema.sql).

```
dart run backend/db/apply_app_schema.dart          # dry run
dart run backend/db/apply_app_schema.dart --yes    # DROP SCHEMA app CASCADE, then recreate
dart run backend/db/seed_app.dart --yes            # load reference/content data
```

`apply_app_schema.dart` only ever touches the `app` schema — `public` and
`_prisma_migrations` are never referenced. Note the Data API (PostgREST) above
exposes `public` only; point the app at `app` via `search_path` or qualified
names.

Check the connection on its own with:

```
dart run tool/neon_ping.dart
```

## Notes

- `db/introspect.dart` currently borrows the Flutter project's `postgres`
  dependency so it can run from the repo root without a second `pub get`. When
  the backend grows its own package, move it and give it its own `pubspec`.
- Direct DB credentials must not ship in a public app build — see the warning in
  `lib/data/neon/neon_database.dart`.
