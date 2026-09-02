import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import 'neon_secret.dart';

/// Talks to Neon over its HTTP SQL endpoint (`https://<host>/sql`) rather than a
/// raw Postgres socket.
///
/// The socket driver ([NeonDatabase]) needs an outbound connection on 5432 with
/// Neon-specific TLS/SNI. That is unreliable from a phone and, worse, fails
/// silently in a `--release` build where `debugPrint` is stripped — which is why
/// sign-in and registration rows were never reaching `app.users`. This endpoint
/// is plain HTTPS on 443, behaves identically in debug and release, and is the
/// same transport Neon's own serverless driver uses.
///
/// The connection string is injected at build time and never committed:
///
/// ```
/// flutter run  --dart-define-from-file=.env
/// flutter build apk --release --dart-define-from-file=.env
/// ```
///
/// with a git-ignored `.env` at the repo root holding
/// `DATABASE_URL=postgresql://USER:PASSWORD@HOST/neondb?sslmode=require`.
class NeonHttp {
  NeonHttp._();

  static final NeonHttp instance = NeonHttp._();

  /// The connection string, from the git-ignored [kNeonDatabaseUrl] (generated
  /// from `.env` by `tool/gen_neon_secret.dart`), or `--dart-define=DATABASE_URL`
  /// as a fallback for environments where the command line is safe.
  static const String _databaseUrl = kNeonDatabaseUrl != ''
      ? kNeonDatabaseUrl
      : String.fromEnvironment('DATABASE_URL');

  /// The raw compiled-in value, exposed so a diagnostic can show its length
  /// without leaking the credentials.
  static String get rawUrl => _databaseUrl;

  /// `true` when `flutter test` is running — the connection string is now a
  /// compiled-in const, so without this check every repository would fire real
  /// HTTP at Neon during the test run.
  static final bool _underTest =
      Platform.environment.containsKey('FLUTTER_TEST');

  /// Whether a real database write/read should happen: a connection string is
  /// compiled in and we are not inside a test.
  static bool get isConfigured => _databaseUrl.isNotEmpty && !_underTest;

  final http.Client _client = http.Client();
  Uri? _endpoint;

  /// `https://<host>/sql`, taken from the connection string's host.
  Uri get _sqlEndpoint =>
      _endpoint ??= Uri.parse('https://${Uri.parse(_databaseUrl).host}/sql');

  /// Runs [sql] with positional parameters (`$1`, `$2`, …) and returns the rows
  /// as string-keyed maps. Every value comes back as a `String?` (or a nested
  /// JSON value) — callers parse what they need. Throws [NeonHttpException] on a
  /// non-200 response and rethrows transport errors.
  Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    if (!isConfigured) {
      throw StateError(
        'DATABASE_URL was not set at build time. Run with '
        '--dart-define-from-file=.env',
      );
    }

    final response = await _client
        .post(
          _sqlEndpoint,
          headers: const {
            'Content-Type': 'application/json',
            'Neon-Connection-String': _databaseUrl,
            'Neon-Raw-Text-Output': 'true',
            'Neon-Array-Mode': 'false',
          },
          body: jsonEncode({'query': sql, 'params': params}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw NeonHttpException(response.statusCode, response.body);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['rows'] as List<dynamic>? ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
  }

  /// A `SELECT 1` round-trip, used at launch to confirm the endpoint answers.
  Future<bool> ping() async => (await query('select 1 as ok')).isNotEmpty;

  /// Logs [message] under the `neon` tag. Uses `dart:developer` rather than
  /// `debugPrint` so the line still reaches logcat in a release build.
  static void log(String message, {Object? error}) {
    developer.log(message, name: 'neon', error: error);
  }
}

/// Neon's `/sql` endpoint answered with a non-200 — usually a SQL error, whose
/// text is in [body].
class NeonHttpException implements Exception {
  final int statusCode;
  final String body;

  NeonHttpException(this.statusCode, this.body);

  @override
  String toString() => 'NeonHttpException($statusCode): $body';
}
