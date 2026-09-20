// Applies backend/db/app_schema.sql — the Sahakar 360 customer-app schema.
//
//   dart run backend/db/apply_app_schema.dart          # dry run: what it will do
//   dart run backend/db/apply_app_schema.dart --yes    # drop & recreate schema "app"
//
// DESTRUCTIVE for the "app" schema only. It runs:
//
//   DROP SCHEMA IF EXISTS app CASCADE;
//
// then executes app_schema.sql, which recreates the schema from scratch. The
// Prisma-managed tables in "public" (customers, products, wallets, RBAC,
// _prisma_migrations, …) are never referenced and cannot be touched by this.
//
// Reads DATABASE_URL from the environment or `.env` at the repo root.

import 'dart:io';

import 'package:postgres/postgres.dart';

Future<void> main(List<String> args) async {
  final confirmed = args.contains('--yes');

  final url = _databaseUrl();
  if (url == null || url.isEmpty) {
    stderr.writeln('DATABASE_URL not found (env or .env at repo root).');
    exit(1);
  }

  final sqlFile = File('backend/db/app_schema.sql');
  if (!sqlFile.existsSync()) {
    stderr.writeln('backend/db/app_schema.sql not found — run from the repo root.');
    exit(1);
  }
  final sql = sqlFile.readAsStringSync();

  final uri = Uri.parse(url);
  final ui = uri.userInfo.split(':');
  final conn = await Connection.open(
    Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'neondb',
      username: Uri.decodeComponent(ui.first),
      password: ui.length > 1 ? Uri.decodeComponent(ui[1]) : null,
    ),
    settings: const ConnectionSettings(
      sslMode: SslMode.require,
      applicationName: 'shield-app-schema',
    ),
  );

  Future<int> appTableCount() async => (await conn.execute(
        "select count(*) from information_schema.tables "
        "where table_schema = 'app' and table_type = 'BASE TABLE'",
      )).first.first as int;

  final dbName =
      uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'neondb';
  final before = await appTableCount();
  final publicCount = (await conn.execute(
    "select count(*) from information_schema.tables "
    "where table_schema = 'public' and table_type = 'BASE TABLE'",
  )).first.first as int;

  stdout
    ..writeln('Database : ${uri.host}/$dbName')
    ..writeln('Schema   : app  (existing tables: $before)')
    ..writeln('Untouched: public  ($publicCount Prisma-managed tables)')
    ..writeln('Action   : DROP SCHEMA IF EXISTS app CASCADE; then run '
        'app_schema.sql (${sql.length} bytes)');

  if (!confirmed) {
    stdout
      ..writeln()
      ..writeln('Dry run. Re-run with --yes to apply.');
    await conn.close();
    return;
  }

  stdout.writeln('\nDropping schema app…');
  await conn.execute('DROP SCHEMA IF EXISTS app CASCADE',
      queryMode: QueryMode.simple);

  stdout.writeln('Applying app_schema.sql…');
  await conn.execute(sql, queryMode: QueryMode.simple);

  final after = await appTableCount();
  final types = (await conn.execute(
    "select count(*) from pg_type t join pg_namespace n on n.oid = t.typnamespace "
    "where n.nspname = 'app' and t.typtype = 'e'",
  )).first.first as int;

  stdout
    ..writeln('\nDone.')
    ..writeln('  app tables : $after')
    ..writeln('  app enums  : $types')
    ..writeln('\nNext: dart run backend/db/seed_app.dart --yes');

  await conn.close();
}

String? _databaseUrl() {
  final env = Platform.environment['DATABASE_URL'];
  if (env != null && env.isNotEmpty) return env;
  final file = File('.env');
  if (!file.existsSync()) return null;
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0 || line.substring(0, eq).trim() != 'DATABASE_URL') continue;
    var v = line.substring(eq + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }
  return null;
}
