import '../../module/registration/registration_service.dart';
import 'backend_http.dart';

/// Saves and reads back the registration profile through `backend/api`'s
/// `PATCH`/`GET /v1/member/me` — see `identity.service.ts`'s `updateProfile`.
///
/// [Registration.storeId] is the app's stable store *code*
/// (`ShieldStore.id`), but the backend's `homeStoreId` is the numeric
/// `app.shield_store` row id — this resolves between the two via the
/// public store list (cached — it's near-static), the same pattern
/// `WalletRepository` uses for membership tiers.
///
/// The registration bonus is credited automatically by the backend the
/// first time a save completes (see that endpoint's own doc) — this class
/// has no separate "award" call, unlike the old direct-Neon
/// `MemberRepository` + `RewardsRepository.credit` pair.
class MemberRepository {
  MemberRepository._();

  static final MemberRepository instance = MemberRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  Map<String, int>? _storeIdByCode;
  Map<int, String>? _storeCodeById;

  /// Saves [registration]. Throws on failure — same contract as the old
  /// direct-Neon version; callers already wrap this and log rather than
  /// propagate.
  Future<void> upsertRegistration(Registration registration) async {
    if (!isAvailable) {
      return;
    }
    final storeId = await _storeIdFor(registration.storeId);
    await BackendHttp.instance.request(
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
        if (storeId != null) 'homeStoreId': storeId,
      },
    );
    BackendHttp.log('upsertRegistration: saved ${registration.phone}');
  }

  /// Reads back a previously completed registration — null when the backend
  /// is off, the profile isn't finished yet (`registrationCompletedAt` is
  /// only set on a successful save), or essential fields are missing.
  /// [phone] is accepted for parity with the old direct-Neon signature but
  /// unused — the backend resolves identity from the session.
  Future<Registration?> fetchByPhone(String phone) async {
    if (!isAvailable) {
      return null;
    }
    try {
      final me = await BackendHttp.instance.request('GET', '/v1/member/me')
          as Map<String, dynamic>;
      if (me['registrationCompletedAt'] == null) {
        return null;
      }
      final homeStoreId = me['homeStoreId'];
      final storeCode = homeStoreId == null
          ? null
          : await _storeCodeFor((homeStoreId as num).toInt());
      final dob = me['dob'] as String?;
      if (storeCode == null || dob == null) {
        return null;
      }
      final genderName = (me['gender'] as String?)?.toUpperCase();

      return Registration(
        name: (me['name'] as String?) ?? '',
        phone: phone,
        email: (me['email'] as String?) ?? '',
        gender: Gender.values.firstWhere(
          (gender) => gender.name.toUpperCase() == genderName,
          orElse: () => Gender.other,
        ),
        dob: DateTime.parse(dob),
        address: (me['address'] as String?) ?? '',
        place: (me['place'] as String?) ?? '',
        pincode: (me['pincode'] as String?) ?? '',
        state: (me['state'] as String?) ?? '',
        storeId: storeCode,
      );
    } catch (error) {
      BackendHttp.log('fetchByPhone failed', error: error);
      return null;
    }
  }

  Future<int?> _storeIdFor(String code) async {
    final map = await _ensureStoreMaps();
    return map[code];
  }

  Future<String?> _storeCodeFor(int id) async {
    await _ensureStoreMaps();
    return _storeCodeById?[id];
  }

  Future<Map<String, int>> _ensureStoreMaps() async {
    final cached = _storeIdByCode;
    if (cached != null) {
      return cached;
    }
    final rows = await BackendHttp.instance.request(
      'GET',
      '/v1/public/catalogue/stores',
      auth: false,
    ) as List<dynamic>;
    final byCode = <String, int>{};
    final byId = <int, String>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final code = (row['code'] ?? '').toString();
      final id = row['id'];
      if (code.isEmpty || id == null) continue;
      final numericId = (id as num).toInt();
      byCode[code] = numericId;
      byId[numericId] = code;
    }
    _storeIdByCode = byCode;
    _storeCodeById = byId;
    return byCode;
  }

  /// `1994-09-04` — an unambiguous value for the backend's `dob` field.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
