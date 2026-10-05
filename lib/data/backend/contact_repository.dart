import 'backend_http.dart';

/// The admin desk's WhatsApp number, read from `GET /v1/public/catalogue/contact`
/// (set in the admin console — `app.app_setting`, migration 0073).
///
/// Public, so a member can reach the desk before signing in or registering.
/// Null when the backend is off or unreachable, and blank when no number has
/// been set yet — either way the caller hides the option rather than showing a
/// dead button.
class ContactRepository {
  ContactRepository._();

  static final ContactRepository instance = ContactRepository._();

  Future<String?> adminWhatsapp() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final body = await BackendHttp.instance.request(
        'GET',
        '/v1/public/catalogue/contact',
        auth: false,
      ) as Map<String, dynamic>;
      final number = (body['adminWhatsapp'] as String?)?.trim() ?? '';
      return number.isEmpty ? null : number;
    } catch (error) {
      BackendHttp.log('ContactRepository.adminWhatsapp failed', error: error);
      return null;
    }
  }
}
