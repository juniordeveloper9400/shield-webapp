import 'package:flutter/foundation.dart';

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
      final body =
          await BackendHttp.instance.request('GET', '/v1/member/referrals/code')
              as Map<String, dynamic>;
      return body['code'] as String?;
    } catch (error) {
      BackendHttp.log('ReferralRepository.ensureCodeFor failed', error: error);
      return null;
    }
  }

  /// The member's real standing: who has joined on their code and how far each
  /// has got, how many invites have transacted, how many went on to activate a
  /// privilege plan, and the Sahakar money that
  /// actually earned — `sahakarMoneyEarned`, the real sum of every
  /// `app.referral.commission_amount` credited to this member as an
  /// inviter (see `ReferralService.getProgress`'s own doc), not a
  /// client-side 2% projection the way this used to work before the
  /// backend actually paid the commission out.
  Future<ReferralProgress?> progressFor(String phone) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final body =
          await BackendHttp.instance.request(
                'GET',
                '/v1/member/referrals/progress',
              )
              as Map<String, dynamic>;
      final directReferrals = _int(body['directReferrals']);
      final activatedCards = (body['activatedWalletCards'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final invitees = inviteesFrom(
        (body['invitees'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>(),
      );
      return ReferralProgress(
        directReferrals: directReferrals,
        // Joined but not yet transacted: the backend counts them apart so the
        // screen can show a sign-up the moment it happens.
        pendingReferrals: _int(body['pendingReferrals']),
        invitees: invitees,
        plansActivated: activatedCards.length,
        sahakarMoney: _int(body['sahakarMoneyEarned']),
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
      final body =
          await BackendHttp.instance.request(
                'POST',
                '/v1/member/referrals/apply-code',
                body: {'code': trimmed},
              )
              as Map<String, dynamic>;
      return body['linked'] as String?;
    } catch (error) {
      BackendHttp.log('ReferralRepository.applyCode failed', error: error);
      return null;
    }
  }

  /// The code the signed-in member themselves signed up with, if any —
  /// `GET /v1/member/referrals/used-code`, see `ReferralService.getUsedCode`'s
  /// own doc. Lets the registration form show a member's own referral/agent
  /// code back to them on a later visit, rather than only while they are
  /// still typing it in. [phone] is accepted for parity with the other
  /// signatures here but unused — the backend resolves identity from the
  /// session. Null when nothing applied, or the backend is unreachable.
  Future<String?> usedCodeFor(String phone) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final body =
          await BackendHttp.instance.request(
                'GET',
                '/v1/member/referrals/used-code',
              )
              as Map<String, dynamic>;
      return body['code'] as String?;
    } catch (error) {
      BackendHttp.log('ReferralRepository.usedCodeFor failed', error: error);
      return null;
    }
  }

  /// Reads the `invitees` the progress route returns, in the order given. The
  /// backend has already cut each name to first name and last initial; a person
  /// whose status is not one of a member who has joined is left out.
  @visibleForTesting
  static List<ReferredMember> inviteesFrom(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final people = <ReferredMember>[];
    for (final row in rows) {
      final stage = ReferredStage.fromStatus(row['status']?.toString());
      if (stage == null) continue;
      final name = row['name']?.toString().trim() ?? '';
      people.add(
        ReferredMember(
          name: name.isEmpty ? 'A friend' : name,
          stage: stage,
          joinedAt: _date(row['registeredAt']),
          transactedAt: _date(row['transactedAt']),
          planActivatedAt: _date(row['planActivatedAt']),
        ),
      );
    }
    return people;
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static int _int(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return num.tryParse(value.toString())?.toInt() ?? 0;
  }
}
