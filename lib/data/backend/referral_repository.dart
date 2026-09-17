import '../../module/refer/referral_level.dart';
import 'backend_http.dart';

/// Reads the signed-in member's refer-and-earn standing through
/// `backend/api`'s `/v1/member/referrals/*` routes — see
/// `referral.service.ts`.
///
/// Advancing the member's own inbound referral to `TRANSACTED` isn't
/// ported: the backend does that automatically now, inside the checkout
/// transaction itself (`order.service.ts`'s `checkout`).
///
/// Best-effort, like every repository here: an unconfigured backend or the
/// network down leaves reads at null so the caller keeps whatever it
/// already had rather than treating a blip as "nothing referred yet".
class ReferralRepository {
  const ReferralRepository._();

  static const ReferralRepository instance = ReferralRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// The member's own invite code, generating and saving one on the
  /// backend the first time it's asked for. [phone] is accepted for parity
  /// with the old direct-Neon signature but unused — the backend resolves
  /// identity from the session.
  Future<String?> ensureCodeFor(String phone) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final body = await BackendHttp.instance.request('GET', '/v1/member/referrals/code')
          as Map<String, dynamic>;
      return body['code'] as String?;
    } catch (error) {
      BackendHttp.log('ReferralRepository.ensureCodeFor failed', error: error);
      return null;
    }
  }

  /// The member's real standing: how many invites have transacted, how many
  /// went on to activate a privilege plan, and the Sahakar money that
  /// earned — computed here client-side from the raw activated-card amounts
  /// the backend returns, via [ReferralLadder.planCommissionOn], the exact
  /// same formula and place it has always lived.
  Future<ReferralProgress?> progressFor(String phone) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final body = await BackendHttp.instance.request('GET', '/v1/member/referrals/progress')
          as Map<String, dynamic>;
      final directReferrals = _int(body['directReferrals']);
      final activatedCards = (body['activatedWalletCards'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      var sahakarMoney = 0;
      for (final card in activatedCards) {
        sahakarMoney += ReferralLadder.planCommissionOn(_int(card['amount']));
      }
      return ReferralProgress(
        directReferrals: directReferrals,
        plansActivated: activatedCards.length,
        sahakarMoney: sahakarMoney,
      );
    } catch (error) {
      BackendHttp.log('ReferralRepository.progressFor failed', error: error);
      return null;
    }
  }

  /// Resolves whatever was typed into the "Referral ID" field at
  /// registration — `POST /v1/member/referrals/apply-code`, see
  /// `ReferralService.applySignupCode`'s own doc for what it can resolve
  /// to (an agent's own code, or a fellow member's referral code — the one
  /// field accepts either, and they never collide). Fire-and-forget by
  /// design, same as every other write here: a bad or already-used code
  /// must never hold up registration, so the caller does not need to
  /// react to the result — this only returns it for callers that want to.
  Future<String?> applyCode(String code) async {
    final trimmed = code.trim();
    if (!BackendHttp.isConfigured || trimmed.isEmpty) {
      return null;
    }
    try {
      final body = await BackendHttp.instance.request(
        'POST',
        '/v1/member/referrals/apply-code',
        body: {'code': trimmed},
      ) as Map<String, dynamic>;
      return body['linked'] as String?;
    } catch (error) {
      BackendHttp.log('ReferralRepository.applyCode failed', error: error);
      return null;
    }
  }

  static int _int(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return num.tryParse(value.toString())?.toInt() ?? 0;
  }
}
