import 'package:flutter/foundation.dart';

import '../../module/registration/registration_service.dart';
import 'backend_http.dart';

/// Why a registration save was refused, in words to show the member.
///
/// Thrown by [MemberRepository.upsertRegistration] so the form can stay open
/// and say what went wrong instead of celebrating a registration that never
/// reached the database.
class RegistrationSaveException implements Exception {
  final String message;

  /// The backend's error code (`STORE_UNAVAILABLE`, …), or null when the
  /// request never got an answer (offline, timed out).
  final String? code;

  const RegistrationSaveException(this.message, {this.code});

  @override
  String toString() => 'RegistrationSaveException($code): $message';
}

/// What [MemberRepository.fetchRegistration] found out.
enum RegistrationLookupStatus {
  /// The member finished registration — [RegistrationLookup.registration] is set.
  registered,

  /// The backend answered, and this member has not registered yet.
  notRegistered,

  /// No answer — offline, the backend down, or no session yet. Says nothing
  /// about whether the member is registered, so it must never be read as "not".
  unavailable,
}

@immutable
class RegistrationLookup {
  final RegistrationLookupStatus status;
  final Registration? registration;

  const RegistrationLookup.registered(Registration this.registration)
    : status = RegistrationLookupStatus.registered;

  const RegistrationLookup.notRegistered()
    : status = RegistrationLookupStatus.notRegistered,
      registration = null;

  const RegistrationLookup.unavailable()
    : status = RegistrationLookupStatus.unavailable,
      registration = null;
}

/// Saves and reads back the registration profile through `backend/api`'s
/// `PATCH`/`GET /v1/member/me` — see `identity.service.ts`.
///
/// Whether a member is registered is the backend's own call
/// (`registrationCompletedAt`, only ever set by the server on the first
/// successful save) — never inferred from what else happens to be filled in.
/// The branch travels as its stable code (`ShieldStore.id`, `SHD-MEL`) both
/// ways: the backend resolves it, and returns it whether or not that branch is
/// still active, so a registration reads back the same after a branch is
/// switched off.
///
/// The registration bonus is credited automatically by the backend the
/// first time a save completes (see that endpoint's own doc) — this class
/// has no separate "award" call.
class MemberRepository {
  MemberRepository._({BackendHttp? http})
    : _http = http ?? BackendHttp.instance;

  static final MemberRepository instance = MemberRepository._();

  /// Test-only: an instance wired to an injected [BackendHttp] (typically
  /// [BackendHttp.test] around a `MockClient`).
  @visibleForTesting
  factory MemberRepository.test({required BackendHttp http}) =>
      MemberRepository._(http: http);

  final BackendHttp _http;

  bool get isAvailable => _http.isEnabled;

  /// Whether a backend session exists yet. After a restored launch it comes a
  /// moment after the app is on screen, and nothing authenticated can be
  /// asked before it does.
  bool get hasSession => _http.isSignedIn;

  Map<int, String>? _storeCodeById;

  /// Saves [registration]. Throws [RegistrationSaveException] when the backend
  /// refuses it or cannot be reached — the caller must not treat the member as
  /// registered until this returns.
  Future<void> upsertRegistration(Registration registration) async {
    if (!isAvailable) {
      return;
    }
    try {
      await _http.request(
        'PATCH',
        '/v1/member/me',
        body: {
          'name': registration.name,
          if (registration.email.isNotEmpty) 'email': registration.email,
          'gender': registration.gender.name.toUpperCase(),
          'dob': _isoDate(registration.dob),
          'address': registration.address,
          'place': registration.place,
          'pincode': registration.pincode,
          'state': registration.state,
          if (registration.storeId.isNotEmpty)
            'homeStoreCode': registration.storeId,
        },
      );
    } on BackendHttpException catch (error) {
      BackendHttp.log('upsertRegistration refused', error: error);
      throw RegistrationSaveException(_describe(error), code: error.code);
    } catch (error) {
      BackendHttp.log('upsertRegistration failed', error: error);
      throw const RegistrationSaveException(
        'We couldn’t save your registration. Check your connection and try '
        'again.',
      );
    }
    BackendHttp.log('upsertRegistration: saved ${registration.phone}');
  }

  /// Reads the signed-in member's registration back.
  ///
  /// Distinguishes "the backend says not registered" from "could not ask" —
  /// the second must never be mistaken for the first, or a registered member
  /// is told to register again just because the network hiccuped, or because
  /// this ran a moment before the backend session was ready.
  ///
  /// [phone] labels the returned profile; the backend resolves identity from
  /// the session.
  Future<RegistrationLookup> fetchRegistration(String phone) async {
    if (!isAvailable) {
      return const RegistrationLookup.unavailable();
    }
    final Map<String, dynamic> me;
    try {
      me = await _http.request('GET', '/v1/member/me') as Map<String, dynamic>;
    } catch (error) {
      BackendHttp.log('fetchRegistration failed', error: error);
      return const RegistrationLookup.unavailable();
    }
    if (me['registrationCompletedAt'] == null) {
      return const RegistrationLookup.notRegistered();
    }

    // Registered is the server's word. The rest of the profile is best-effort
    // detail: a missing field must never turn a registered member back into an
    // unregistered one.
    final genderName = (me['gender'] as String?)?.toUpperCase();
    return RegistrationLookup.registered(
      Registration(
        name: (me['name'] as String?) ?? '',
        phone: phone,
        email: (me['email'] as String?) ?? '',
        gender: Gender.values.firstWhere(
          (gender) => gender.name.toUpperCase() == genderName,
          orElse: () => Gender.other,
        ),
        dob:
            DateTime.tryParse((me['dob'] as String?) ?? '') ??
            DateTime.utc(1970),
        address: (me['address'] as String?) ?? '',
        place: (me['place'] as String?) ?? '',
        pincode: (me['pincode'] as String?) ?? '',
        state: (me['state'] as String?) ?? '',
        storeId: await _storeCodeOf(me),
      ),
    );
  }

  /// The branch code from `GET /me` (`homeStoreCode`, sent whether or not the
  /// branch is active). Older backends only send the numeric `homeStoreId`; that
  /// is resolved through the public store list, which only carries active
  /// branches — so an empty string ("no known branch") is a normal answer.
  Future<String> _storeCodeOf(Map<String, dynamic> me) async {
    final code = (me['homeStoreCode'] as String?)?.trim();
    if (code != null && code.isNotEmpty) {
      return code;
    }
    final id = me['homeStoreId'];
    if (id is! num) {
      return '';
    }
    try {
      final byId = _storeCodeById ??= await _loadStoreCodes();
      return byId[id.toInt()] ?? '';
    } catch (error) {
      BackendHttp.log('store code lookup failed', error: error);
      return '';
    }
  }

  Future<Map<int, String>> _loadStoreCodes() async {
    final rows =
        await _http.request('GET', '/v1/public/catalogue/stores', auth: false)
            as List<dynamic>;
    final byId = <int, String>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final code = (row['code'] ?? '').toString();
      final id = row['id'];
      if (code.isNotEmpty && id is num) {
        byId[id.toInt()] = code;
      }
    }
    return byId;
  }

  /// A refusal in words to show the member — the backend's own message where it
  /// wrote one for a person (`STORE_UNAVAILABLE`), otherwise something generic.
  static String _describe(BackendHttpException error) {
    if (error.code == 'STORE_UNAVAILABLE' && error.message.isNotEmpty) {
      return error.message;
    }
    if (error.statusCode == 401) {
      return 'Your session has ended. Sign in again, then save your '
          'registration.';
    }
    if (error.statusCode == 429) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    return 'We couldn’t save your registration. Please try again.';
  }

  /// `1994-09-04` — an unambiguous value for the backend's `dob` field.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
