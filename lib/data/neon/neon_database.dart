import 'dart:io' show Platform;

import 'package:postgres/postgres.dart';

import 'neon_secret.dart';

/// The Neon Postgres connection string. Comes from the git-ignored
/// `lib/data/neon/neon_secret.dart` ([kNeonDatabaseUrl]), which
/// `dart run tool/gen_neon_secret.dart` writes from `.env`; falls back to
/// `--dart-define=DATABASE_URL` where the command line is safe (not Windows —
/// `flutter.bat` runs under cmd.exe and eats the `&` in the URL).
const String _databaseUrl = kNeonDatabaseUrl != ''
    ? kNeonDatabaseUrl
    : String.fromEnvironment('DATABASE_URL');

/// The application name Postgres records for connections from this app, so the
/// Neon dashboard can tell them apart from an admin tool or a migration run.
const String _appName = 'shield-app';

/// A single shared connection to the Neon Postgres database.
///
/// The client talks to Neon directly. That is only acceptable for an internal
/// or staff build: the connection string is embedded in the compiled binary and
/// can be extracted from it. A public release must reach the database through a
/// server API rather than shipping credentials.
///
/// Native only — the `postgres` driver uses `dart:io` sockets, so this does not
/// work on Flutter web.
class NeonDatabase {
  NeonDatabase._();

  static final NeonDatabase instance = NeonDatabase._();

  /// `true` under `flutter test` — the connection string is a compiled-in const
  /// now, so this keeps the socket from being opened during a test run.
  static final bool _underTest =
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Whether a real connection should be opened: a string is compiled in and we
  /// are not inside a test.
  static bool get isConfigured => _databaseUrl.isNotEmpty && !_underTest;

  Connection? _connection;
  Future<Connection>? _pending;

  bool get isOpen => _connection?.isOpen ?? false;

  /// The open connection, opening it on first use. Callers that arrive while
  /// the first open is still in flight all wait on that same attempt rather
  /// than starting their own.
  Future<Connection> connection() {
    final open = _connection;
    if (open != null && open.isOpen) {
      return Future.value(open);
    }
    return _pending ??= _open();
  }

  Future<Connection> _open() async {
    try {
      final conn = await Connection.open(
        _endpoint(),
        settings: ConnectionSettings(
          sslMode: _sslMode(),
          applicationName: _appName,
          connectTimeout: const Duration(seconds: 15),
        ),
      );
      _connection = conn;
      return conn;
    } finally {
      _pending = null;
    }
  }

  /// Opens the connection if needed and runs `SELECT 1` — a cheap check that
  /// the credentials work and the database is reachable.
  Future<bool> ping() async {
    final conn = await connection();
    final result = await conn.execute('SELECT 1');
    return result.isNotEmpty;
  }

  /// Closes the connection. Safe to call when nothing is open.
  Future<void> close() async {
    final conn = _connection;
    _connection = null;
    _pending = null;
    await conn?.close();
  }

  /// `DATABASE_URL` parsed into the host/port/database/credentials the driver
  /// needs. Parsed by hand rather than with [Connection.openFromUrl] so that
  /// the extra query parameters Neon and its pooler append — `channel_binding`,
  /// `options`, `pgbouncer` — do not cause a parse failure.
  static Endpoint _endpoint() {
    if (!isConfigured) {
      throw StateError(
        'DATABASE_URL was not set at build time. Run the app with '
        '--dart-define-from-file=.env (see .env.example).',
      );
    }

    final uri = Uri.parse(_databaseUrl);
    if (uri.host.isEmpty) {
      throw StateError('DATABASE_URL has no host: "$_databaseUrl"');
    }

    final userInfo = uri.userInfo.split(':');
    final database = uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.first)
        : 'neondb';

    return Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: database,
      username: userInfo.isNotEmpty && userInfo.first.isNotEmpty
          ? Uri.decodeComponent(userInfo.first)
          : null,
      password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : null,
    );
  }

  /// The TLS mode from `?sslmode=`. Neon always needs TLS, so anything other
  /// than an explicit `disable` / `verify-*` falls back to `require`.
  static SslMode _sslMode() {
    switch (Uri.parse(_databaseUrl).queryParameters['sslmode']) {
      case 'disable':
        return SslMode.disable;
      case 'verify-ca':
      case 'verify-full':
        return SslMode.verifyFull;
      default:
        return SslMode.require;
    }
  }
}
