import '../../module/location/address_book.dart';
import 'backend_http.dart';

/// Creates delivery addresses through `backend/api`'s
/// `POST /v1/member/addresses` — see `identity.service.ts`'s `createAddress`.
///
/// [AddressBook] itself stays pure in-memory (nothing here reads it back);
/// this exists only so checkout flows (standard and prescription) can turn
/// the member's chosen [Address] into a real backend row id to attach to
/// the order. The backend has no dedup, so this is create-on-every-checkout
/// rather than reuse — a minor inefficiency, not a correctness concern.
class AddressRepository {
  const AddressRepository._();

  static const AddressRepository instance = AddressRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

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
