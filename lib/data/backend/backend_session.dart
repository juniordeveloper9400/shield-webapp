import 'package:flutter/foundation.dart';

import 'backend_http.dart';

/// The member session bridge to `backend/api`: restores, adopts, and
/// revokes the backend-issued access/refresh token pair. Sign-in itself is
/// the MSG91-backed OTP flow in `auth_service.dart`, which returns tokens
/// that [setTokens] adopts.
class BackendSession {
  BackendSession._({BackendHttp? http}) : _http = http ?? BackendHttp.instance;

  static final BackendSession instance = BackendSession._();

  /// Test-only: an instance wired to an injected [BackendHttp] (typically
  /// [BackendHttp.test] around a `MockClient`) instead of the real
  /// singleton, so this class can be exercised without a live backend.
  @visibleForTesting
  factory BackendSession.test({required BackendHttp http}) =>
      BackendSession._(http: http);

  final BackendHttp _http;

  bool get isSignedIn => _http.isSignedIn;

  /// Restores a session from a refresh token persisted on an earlier run —
  /// call once at app launch, alongside `MemberRepository`'s own
  /// phone-based `restoreSession`. Returns whether a session was actually
  /// restored, so a caller can send the member back through OTP sign-in
  /// when there was no persisted one to restore (see
  /// `AuthService.restoreSession`'s doc). Never throws.
  Future<bool> restore() async {
    try {
      return await _http.restoreSession();
    } catch (error) {
      BackendHttp.log('restore failed', error: error);
      return false;
    }
  }

  /// Adopts a token pair the caller already minted some other way — the
  /// MSG91-backed member OTP flow's `/otp/verify` and `/otp/register` return
  /// a session directly in the same call that confirms the code, so there
  /// is no separate exchange step. See `AuthService`'s `BackendMemberOtpTransport`.
  Future<void> setTokens({required String accessToken, required String refreshToken}) {
    return _http.setSession(accessToken: accessToken, refreshToken: refreshToken);
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
