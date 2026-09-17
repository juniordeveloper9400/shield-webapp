import 'backend_http.dart';

/// Real branch data from `backend/api`'s public catalogue —
/// `GET /v1/public/catalogue/stores` — the one place a real phone number for
/// a branch actually lives. `StoreDirectory`
/// (`lib/module/registration/shield_store.dart`) is a client-side fixture
/// whose own `phone` field is deliberately always blank (see its own doc);
/// this repository is what fills that gap for anything that needs to show a
/// member a number they can actually call.
///
/// Read-only, best-effort like every repository here: an unconfigured or
/// unreachable backend leaves a lookup at null rather than throwing.
class StoreRepository {
  StoreRepository._();

  static final StoreRepository instance = StoreRepository._();

  /// Cached for the life of the app — the store list is near-static
  /// reference data, the same treatment `WalletRepository`'s tier-id cache
  /// gives its own.
  Map<String, String>? _phoneByCode;

  /// The branch phone number for [code] (`ShieldStore.id`, e.g. `SHD-MEL`),
  /// or null when the backend has none on file for that branch, the branch
  /// doesn't exist, or the backend is unreachable/unconfigured.
  Future<String?> phoneForCode(String code) async {
    final phones = await _ensurePhones();
    final phone = phones?[code];
    return (phone == null || phone.isEmpty) ? null : phone;
  }

  Future<Map<String, String>?> _ensurePhones() async {
    final cached = _phoneByCode;
    if (cached != null) {
      return cached;
    }
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/catalogue/stores',
        auth: false,
      ) as List<dynamic>;
      final map = <String, String>{
        for (final row in rows.cast<Map<String, dynamic>>())
          if (row['code'] != null)
            row['code'].toString(): (row['phone'] ?? '').toString(),
      };
      _phoneByCode = map;
      return map;
    } catch (error) {
      BackendHttp.log('StoreRepository.phoneForCode failed', error: error);
      return null;
    }
  }
}
