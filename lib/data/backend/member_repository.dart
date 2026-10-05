import 'backend_http.dart';

/// The signed-in member's account, read and changed through `backend/api`.
///
/// This used to write `app.users` straight from the app over Neon. That put the
/// database password into every build, so the app no longer talks to the
/// database at all. Each call maps onto a backend route:
///
/// - [phoneExists] → `POST /v1/member/auth/phone-lookup` (public, pre-sign-in)
/// - [nameByPhone] → `GET /v1/member/me`, only while a backend session exists
/// - [deleteAccount] → `DELETE /v1/member/me`
/// - [upsertOnSignIn] → nothing extra: the backend session exchange that
///   [BackendSession] runs right after Firebase sign-in creates or refreshes the
///   row and records the login time itself.
///
/// Best-effort, as before: a failed call returns null (or false) rather than
/// throwing, so sign-in is never blocked by the backend being unreachable. The
/// Firebase session stays the source of truth for whether someone is signed in.
class MemberRepository {
  const MemberRepository._();

  static const MemberRepository instance = MemberRepository._();

  /// Whether the backend is configured for this build.
  bool get isAvailable => BackendHttp.isConfigured;

  /// Kept so the sign-in call site does not change. The backend session exchange
  /// does this work, so there is nothing to do here.
  Future<void> upsertOnSignIn({
    required String name,
    required String phone,
    String? firebaseUid,
  }) async {}

  /// Deletes the signed-in member's account on the backend (soft: the row keeps
  /// its order history, and the personal fields are cleared). Returns whether the
  /// backend accepted the request.
  Future<bool> deleteAccount(String phone) async {
    if (!BackendHttp.isConfigured) return false;
    try {
      await BackendHttp.instance.request('DELETE', '/v1/member/me');
      return true;
    } catch (error) {
      BackendHttp.log('MemberRepository.deleteAccount failed', error: error);
      return false;
    }
  }

  /// Whether a live account exists for [phone]. Null when the check could not
  /// run, so the caller can let the member through rather than block them on a
  /// network blip.
  Future<bool?> phoneExists(String phone) async {
    if (!BackendHttp.isConfigured) return null;
    try {
      final body = await BackendHttp.instance.request(
        'POST',
        '/v1/member/auth/phone-lookup',
        body: {'phone': phone},
        auth: false,
      );
      if (body is Map && body['exists'] is bool) return body['exists'] as bool;
      return null;
    } catch (error) {
      BackendHttp.log('MemberRepository.phoneExists failed', error: error);
      return null;
    }
  }

  /// The stored name of the signed-in member, or null when there is no backend
  /// session yet or the read failed. Called at launch, when the Firebase profile
  /// carries no display name.
  Future<String?> nameByPhone(String phone) async {
    if (!BackendHttp.isConfigured) return null;
    try {
      final body = await BackendHttp.instance.request('GET', '/v1/member/me');
      if (body is Map) {
        final name = body['name'];
        if (name is String && name.trim().isNotEmpty) return name;
      }
      return null;
    } catch (error) {
      BackendHttp.log('MemberRepository.nameByPhone failed', error: error);
      return null;
    }
  }

  /// Kept so the restore path does not change. The backend records the login
  /// time on each session exchange, so there is nothing extra to send here.
  Future<void> touchLogin(String phone) async {}
}
