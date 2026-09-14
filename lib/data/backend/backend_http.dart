import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../neon/_flutter_test_env.dart'
    if (dart.library.io) '../neon/_flutter_test_env_io.dart';

/// Talks to `backend/api` over plain HTTPS — no credential of any kind is
/// compiled into this client, unlike [NeonHttp] (`lib/data/neon/neon_http.dart`),
/// which ships the Neon database password. Session state (a short-lived
/// access token, a longer-lived refresh token) is issued by the backend at
/// sign-in, not baked in at build time.
///
/// Shape deliberately mirrors `NeonHttp`: private singleton constructor,
/// an `isConfigured` guard, a `--dart-define` base URL, and a
/// `dart:developer`-based [log] so log lines survive a release build. See
/// that file's own doc comment for why `dart:developer` over `debugPrint`.
class BackendHttp {
  BackendHttp._() : _client = http.Client(), _forceConfigured = null;

  /// Test-only: builds an instance around [client] with [isConfigured]'s
  /// build-time/test-environment gate bypassed, so `request`/`_refresh`'s
  /// actual protocol logic (401-retry, error parsing) can run against a
  /// [http.testing.MockClient] under `flutter test` — which
  /// [isConfigured] otherwise always reports false under, by design (see
  /// `NeonHttp._underTest`'s doc). Does not affect [instance] or the static
  /// [isConfigured] every repository's own `isAvailable`/`_run` checks.
  @visibleForTesting
  BackendHttp.test({required http.Client client})
    : _client = client,
      _forceConfigured = true;

  static final BackendHttp instance = BackendHttp._();

  /// The backend's base URL, e.g. `https://api.shield.example.com`
  /// (no trailing slash). Injected at build time:
  ///
  /// ```
  /// flutter run --dart-define=BACKEND_API_BASE_URL=https://...
  /// ```
  static const String _baseUrl = String.fromEnvironment('BACKEND_API_BASE_URL');

  /// `true` when `flutter test` is running — see `NeonHttp._underTest`'s doc
  /// for why this guard exists.
  static final bool _underTest = isUnderFlutterTest;

  static bool get isConfigured => _baseUrl.isNotEmpty && !_underTest;

  /// Non-null only on a [BackendHttp.test] instance — overrides
  /// [isConfigured] for that instance alone.
  final bool? _forceConfigured;

  bool get _effectivelyConfigured => _forceConfigured ?? isConfigured;

  static const _refreshTokenPrefsKey = 'backend_refresh_token';

  final http.Client _client;

  String? _accessToken;
  String? _refreshToken;

  bool get isSignedIn => _accessToken != null;

  /// Sets the in-memory access token and persists the refresh token for
  /// [restoreSession] to pick up on a later app launch.
  Future<void> setSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _persistRefreshToken(refreshToken);
  }

  /// Drops the session both in memory and in persisted storage.
  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    await _persistRefreshToken(null);
  }

  /// Tries to mint a fresh access token from a refresh token persisted by an
  /// earlier run — call once at app launch, before anything that needs
  /// [isSignedIn] to reflect an existing session. Returns whether it worked.
  Future<bool> restoreSession() async {
    if (!_effectivelyConfigured) {
      return false;
    }
    final persisted = await _loadPersistedRefreshToken();
    if (persisted == null) {
      return false;
    }
    _refreshToken = persisted;
    return _refresh();
  }

  /// Runs a `GET`/`POST`/`PATCH`/`DELETE` against [path] (e.g.
  /// `/v1/agent/team`), optionally as JSON [body] and/or extra request
  /// [headers] (e.g. `Idempotency-Key` — see `checkout`/`redeem`'s own
  /// callers). Attaches `Authorization: Bearer <token>` unless [auth] is
  /// false (public routes: session/register/refresh). A `401` on an
  /// authenticated call gets one silent refresh-and-retry before this
  /// throws — the same one-shot recovery `shieldweb/src/lib/api.ts` already
  /// does for the admin console.
  ///
  /// Returns the decoded JSON body (a `Map` or `List`), or `null` for a
  /// `204 No Content` response. Throws [BackendHttpException] on any other
  /// non-2xx status, decoded from the backend's `{error:{code,message}}`
  /// envelope where present.
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    bool auth = true,
  }) async {
    if (!_effectivelyConfigured) {
      throw StateError(
        'BACKEND_API_BASE_URL was not set at build time. Run with '
        '--dart-define=BACKEND_API_BASE_URL=...',
      );
    }

    var response = await _send(method, path, body: body, headers: headers, auth: auth);
    if (response.statusCode == 401 && auth && _refreshToken != null) {
      if (await _refresh()) {
        response = await _send(method, path, body: body, headers: headers, auth: auth);
      }
    }
    return _decode(response);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    required bool auth,
  }) {
    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      ...?headers,
    };
    if (auth && _accessToken != null) {
      requestHeaders['Authorization'] = 'Bearer $_accessToken';
    }
    final uri = Uri.parse('$_baseUrl$path');
    final encodedBody = body == null ? null : jsonEncode(body);

    final Future<http.Response> future;
    switch (method) {
      case 'GET':
        future = _client.get(uri, headers: requestHeaders);
      case 'POST':
        future = _client.post(uri, headers: requestHeaders, body: encodedBody);
      case 'PATCH':
        future = _client.patch(uri, headers: requestHeaders, body: encodedBody);
      case 'DELETE':
        future = _client.delete(uri, headers: requestHeaders);
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
    return future.timeout(const Duration(seconds: 20));
  }

  Future<bool> _refresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      return false;
    }
    try {
      final response = await _send(
        'POST',
        '/v1/member/auth/refresh',
        body: {'refreshToken': refreshToken},
        auth: false,
      );
      if (response.statusCode != 200) {
        await clearSession();
        return false;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      _accessToken = decoded['accessToken'] as String;
      final newRefreshToken = decoded['refreshToken'] as String;
      _refreshToken = newRefreshToken;
      await _persistRefreshToken(newRefreshToken);
      return true;
    } catch (error) {
      log('refresh failed', error: error);
      return false;
    }
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return null;
      }
      return jsonDecode(response.body);
    }

    var code = 'UNKNOWN';
    var message = response.body;
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) {
        final error = parsed['error'];
        if (error is Map<String, dynamic>) {
          code = (error['code'] ?? code).toString();
          message = (error['message'] ?? message).toString();
        }
      }
    } catch (_) {
      // Body wasn't JSON — keep the raw text as the message.
    }
    throw BackendHttpException(response.statusCode, code, message);
  }

  Future<void> _persistRefreshToken(String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token == null) {
        await prefs.remove(_refreshTokenPrefsKey);
      } else {
        await prefs.setString(_refreshTokenPrefsKey, token);
      }
    } catch (error) {
      log('persisting refresh token failed', error: error);
    }
  }

  Future<String?> _loadPersistedRefreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_refreshTokenPrefsKey);
    } catch (error) {
      log('loading persisted refresh token failed', error: error);
      return null;
    }
  }

  /// Logs [message] under the `backend` tag. See the class doc for why
  /// `dart:developer` rather than `debugPrint`.
  static void log(String message, {Object? error}) {
    developer.log(message, name: 'backend', error: error);
  }
}

/// The backend answered with a non-2xx status. [code] and [message] come
/// from its `{error:{code,message}}` envelope when present.
class BackendHttpException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  BackendHttpException(this.statusCode, this.code, this.message);

  bool get isNotFound => statusCode == 404;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => 'BackendHttpException($statusCode $code): $message';
}
