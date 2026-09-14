import 'package:flutter/foundation.dart';

import 'backend_http.dart';

/// The Firebase→backend session bridge: after the app finishes its own
/// Firebase phone-auth flow, this exchanges the resulting ID token for a
/// backend-issued session, registering a first-time identity when needed.
///
/// This is additive alongside the existing phone-keyed Neon writes
/// (`MemberRepository.instance.upsertOnSignIn`) — see `auth_service.dart`'s
/// `_afterSignIn`. Nothing about the pre-existing sign-in path is removed;
/// a backend outage here degrades to "agent/investor screens don't load"
/// rather than blocking sign-in entirely.
class BackendSession {
  BackendSession._({BackendHttp? http}) : _http = http ?? BackendHttp.instance;

  static final BackendSession instance = BackendSession._();

  /// Test-only: an instance wired to an injected [BackendHttp] (typically
  /// [BackendHttp.test] around a `MockClient`) instead of the real
  /// singleton, so this class's own orchestration — the register-on-404
  /// fallback — can be exercised without a live backend.
  @visibleForTesting
  factory BackendSession.test({required BackendHttp http}) =>
      BackendSession._(http: http);

  final BackendHttp _http;

  bool get isSignedIn => _http.isSignedIn;

  /// Exchanges [idToken] for a backend session. Tries `POST
  /// /v1/member/auth/session` first (existing member); on a 404 (no
  /// `app.users` row for this identity yet — see `auth.service.ts`'s
  /// `exchangeMemberToken`) falls back to `POST /v1/member/auth/register`
  /// with [name], which creates or backfills the row and returns tokens
  /// directly. Never throws: a backend outage or a stale token just leaves
  /// the caller signed out of the backend (agent/investor screens will show
  /// their empty/unavailable state), matching every Neon repository's
  /// best-effort contract.
  Future<bool> signInWithFirebaseToken(
    String idToken, {
    required String name,
  }) async {
    try {
      final tokens = await _exchangeSession(idToken);
      await _http.setSession(
        accessToken: tokens['accessToken'] as String,
        refreshToken: tokens['refreshToken'] as String,
      );
      return true;
    } on BackendHttpException catch (error) {
      if (!error.isNotFound) {
        BackendHttp.log('signInWithFirebaseToken failed', error: error);
        return false;
      }
      // No app.users row for this identity yet — register it.
      try {
        final tokens = await _http.request(
          'POST',
          '/v1/member/auth/register',
          body: {'idToken': idToken, 'name': name},
          auth: false,
        ) as Map<String, dynamic>;
        await _http.setSession(
          accessToken: tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String,
        );
        return true;
      } catch (registerError) {
        BackendHttp.log('register failed', error: registerError);
        return false;
      }
    } catch (error) {
      BackendHttp.log('signInWithFirebaseToken failed', error: error);
      return false;
    }
  }

  Future<Map<String, dynamic>> _exchangeSession(String idToken) async {
    final result = await _http.request(
      'POST',
      '/v1/member/auth/session',
      body: {'idToken': idToken},
      auth: false,
    );
    return result as Map<String, dynamic>;
  }

  /// Restores a session from a refresh token persisted on an earlier run —
  /// call once at app launch, alongside `MemberRepository`'s own
  /// phone-based `restoreSession`. Never throws.
  Future<void> restore() async {
    try {
      await _http.restoreSession();
    } catch (error) {
      BackendHttp.log('restore failed', error: error);
    }
  }

  /// Revokes the backend session and clears local tokens. Never throws —
  /// sign-out must succeed locally even if the revoke call itself fails.
  Future<void> signOut() async {
    if (_http.isSignedIn) {
      try {
        await _http.request('DELETE', '/v1/member/auth/session');
      } catch (error) {
        BackendHttp.log('signOut revoke failed', error: error);
      }
    }
    await _http.clearSession();
  }
}
