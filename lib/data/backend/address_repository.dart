import '../../module/location/address_book.dart';
import 'backend_http.dart';

/// Reads and writes delivery addresses through `backend/api`'s
/// `GET`/`POST /v1/member/addresses` — see `identity.service.ts`'s
/// `listAddresses`/`createAddress`.
///
/// [AddressBook] is the app's in-memory copy, hydrated from [fetchAll] —
/// see that method's own doc for why it has to be, and [AddressBook]'s doc
/// for what it looked like before it was. The backend has no dedup on
/// [create], so a checkout that creates one is still create-on-every-checkout
/// rather than reuse — a minor inefficiency, not a correctness concern.
class AddressRepository {
  const AddressRepository._();

  static const AddressRepository instance = AddressRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// Every address the member has on file, oldest first — how the app
  /// learns "yes, I already saved one" is still true after a restart or a
  /// web reload, instead of only ever remembering it for as long as
  /// [AddressBook] happens to still be sitting in memory. Null when the
  /// backend is unconfigured or unreachable; never throws.
  Future<List<Address>?> fetchAll() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request('GET', '/v1/member/addresses')
          as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>()) _fromRow(row),
      ];
    } catch (error) {
      BackendHttp.log('AddressRepository.fetchAll failed', error: error);
      return null;
    }
  }

  static Address _fromRow(Map<String, dynamic> row) => Address(
    pincode: (row['pincode'] ?? '').toString(),
    house: (row['house'] ?? '').toString(),
    area: (row['area'] ?? '').toString(),
    landmark: (row['landmark'] ?? '').toString(),
    firstName: (row['firstName'] ?? '').toString(),
    lastName: (row['lastName'] ?? '').toString(),
    phone: (row['phone'] ?? '').toString(),
    label: _labelFor((row['label'] ?? '').toString()),
    patientId: row['patientId']?.toString(),
  );

  static AddressLabel _labelFor(String token) => switch (token.toUpperCase()) {
    'WORK' => AddressLabel.work,
    'OTHER' => AddressLabel.other,
    _ => AddressLabel.home,
  };

  /// Creates [address] and returns its new id, or null when nothing was
  /// written (unconfigured backend, network error).
  Future<int?> create(Address address) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final created = await BackendHttp.instance.request(
        'POST',
        '/v1/member/addresses',
        body: {
          'label': address.label.name.toUpperCase(),
          'house': address.house,
          'area': address.area,
          'landmark': address.landmark,
          'pincode': address.pincode,
          'firstName': address.firstName,
          'lastName': address.lastName,
          'phone': address.phone,
        },
      ) as Map<String, dynamic>;
      return created['id'] as int?;
    } catch (error) {
      BackendHttp.log('AddressRepository.create failed', error: error);
      return null;
    }
  }
}
