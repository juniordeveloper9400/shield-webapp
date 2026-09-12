import 'dart:math';

import '../../module/refer/referral_level.dart';
import 'neon_http.dart';

/// Reads and writes the refer-and-earn graph on Neon: `app.users.referral_code`,
/// and the `app.referral` row that tracks one invitee from sign-up to plan
/// activation.
///
/// Best-effort, the same contract as the other Neon repositories: with no
/// `DATABASE_URL` compiled in or the network down, reads return `null` and
/// writes no-op — the refer & earn screen must never break because the
/// database is unreachable, it just has nothing real to report yet.
class ReferralRepository {
  const ReferralRepository._();

  static const ReferralRepository instance = ReferralRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// The member's own invite code, generating and saving one the first time
  /// it is asked for. Null when the database is unreachable, or [phone] has
  /// no `app.users` row yet (sign-in writes one before this is ever called,
  /// so that should not happen in practice).
  ///
  /// `SHIELD-` plus four digits, retried against the column's `UNIQUE`
  /// constraint — a collision only ever costs another random draw, not a
  /// failed registration.
  Future<String?> ensureCodeFor(String phone) {
    return _run('ensureCodeFor', () async {
      final existing = await NeonHttp.instance.query(
        'SELECT referral_code FROM app.users WHERE phone = \$1',
        [phone],
      );
      final current = existing.isEmpty
          ? null
          : existing.first['referral_code']?.toString();
      if (current != null && current.isNotEmpty) {
        return current;
      }

      final random = Random();
      for (var attempt = 0; attempt < 8; attempt++) {
        final candidate = 'SHIELD-${1000 + random.nextInt(9000)}';
        try {
          final saved = await NeonHttp.instance.query(
            '''
              UPDATE app.users SET referral_code = \$1, updated_at = now()
              WHERE phone = \$2 AND referral_code IS NULL
              RETURNING referral_code
            ''',
            [candidate, phone],
          );
          if (saved.isNotEmpty) {
            return saved.first['referral_code']?.toString();
          }
          // No row moved: either this phone already has a code — another
          // call won the race — or there is no `app.users` row for it yet.
          // Reading it back settles which, without guessing.
          final recheck = await NeonHttp.instance.query(
            'SELECT referral_code FROM app.users WHERE phone = \$1',
            [phone],
          );
          if (recheck.isEmpty) {
            return null;
          }
          final settled = recheck.first['referral_code']?.toString();
          if (settled != null && settled.isNotEmpty) {
            return settled;
          }
          return null;
        } catch (error) {
          // Almost certainly the UNIQUE constraint — another member already
          // holds this candidate. Draw again rather than give up on one clash.
          NeonHttp.log(
            'ensureCodeFor: candidate $candidate taken, retrying',
            error: error,
          );
        }
      }
      return null;
    });
  }

  /// Records that [newMemberPhone] signed up using [code] — the one edge from
  /// inviter to invitee the whole ladder is climbed on.
  ///
  /// Returns `false` (and writes nothing) when the code does not resolve to a
  /// member, resolves to the phone signing up itself, or this phone already
  /// carries a referral row — a member is referred once, and the earliest
  /// attribution is the one that stands.
  Future<bool> recordSignup({
    required String code,
    required String newMemberPhone,
  }) async {
    final result = await _run<bool>('recordSignup', () async {
      final trimmedCode = code.trim();
      if (trimmedCode.isEmpty) {
        return false;
      }

      final inviterRows = await NeonHttp.instance.query(
        'SELECT id, phone FROM app.users WHERE referral_code = \$1',
        [trimmedCode],
      );
      if (inviterRows.isEmpty) {
        return false;
      }
      final inviterId = inviterRows.first['id'];
      final inviterPhone = inviterRows.first['phone']?.toString();
      if (inviterPhone == newMemberPhone) {
        return false; // a code cannot refer its own owner
      }

      final inserted = await NeonHttp.instance.query(
        '''
          WITH invitee AS (
            SELECT id FROM app.users WHERE phone = \$1
          )
          INSERT INTO app.referral (
            inviter_member_id, invitee_member_id, invitee_phone,
            code_used, status, registered_at
          )
          SELECT \$2, invitee.id, \$1, \$3, 'REGISTERED', now()
          FROM invitee
          WHERE NOT EXISTS (
            SELECT 1 FROM app.referral existing
            WHERE existing.invitee_member_id = invitee.id
          )
          RETURNING id
        ''',
        [newMemberPhone, inviterId, trimmedCode],
      );
      if (inserted.isEmpty) {
        return false;
      }

      await NeonHttp.instance.query(
        '''
          UPDATE app.users SET referred_by_member_id = \$1, updated_at = now()
          WHERE phone = \$2 AND referred_by_member_id IS NULL
        ''',
        [inviterId, newMemberPhone],
      );
      NeonHttp.log('recordSignup: $newMemberPhone referred by $inviterPhone');
      return true;
    });
    return result ?? false;
  }

  /// Advances [phone]'s inbound referral (they are the one who was invited)
  /// from `REGISTERED` to `TRANSACTED` — the first paid order they complete.
  ///
  /// A no-op when nobody referred this member, or their referral has already
  /// moved past `REGISTERED`: the status only ever moves forward.
  Future<void> markTransacted(String phone) async {
    await _run('markTransacted', () async {
      await NeonHttp.instance.query(
        '''
          UPDATE app.referral r
          SET status = 'TRANSACTED', transacted_at = now()
          FROM app.users u
          WHERE u.id = r.invitee_member_id AND u.phone = \$1
            AND r.status = 'REGISTERED'
        ''',
        [phone],
      );
    });
  }

  /// The signed-in member's real standing: how many of their invites have
  /// transacted, how many of those went on to activate a privilege plan, and
  /// what that has paid — 2% of each approved load (see
  /// [ReferralLadder.planCommissionOn]), worked out the same way the
  /// commission card on the screen works it out, so the two can never
  /// disagree.
  ///
  /// Null on a failed read; the caller keeps whatever it already had rather
  /// than treating a blip as "nothing referred yet".
  Future<ReferralProgress?> progressFor(String phone) {
    return _run('progressFor', () async {
      final referredRows = await NeonHttp.instance.query(
        '''
          SELECT count(*) AS n
          FROM app.referral r
          JOIN app.users u ON u.id = r.inviter_member_id
          WHERE u.phone = \$1 AND r.status IN ('TRANSACTED', 'PLAN_ACTIVATED')
        ''',
        [phone],
      );
      final directReferrals = _int(
        referredRows.isEmpty ? null : referredRows.first['n'],
      );

      // One row per approved privilege card issued to somebody this member
      // referred — a member can activate more than one card, and each pays
      // its own share.
      final activatedRows = await NeonHttp.instance.query(
        '''
          SELECT wc.amount
          FROM app.referral r
          JOIN app.users inviter  ON inviter.id = r.inviter_member_id
          JOIN app.wallet w       ON w.member_id = r.invitee_member_id
          JOIN app.wallet_card wc ON wc.wallet_id = w.id AND wc.status = 'APPROVED'
          WHERE inviter.phone = \$1
        ''',
        [phone],
      );
      var sahakarMoney = 0;
      for (final row in activatedRows) {
        sahakarMoney += ReferralLadder.planCommissionOn(_int(row['amount']));
      }

      return ReferralProgress(
        directReferrals: directReferrals,
        plansActivated: activatedRows.length,
        sahakarMoney: sahakarMoney,
      );
    });
  }

  static int _int(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return num.tryParse(value.toString())?.toInt() ?? 0;
  }

  Future<T?> _run<T>(String label, Future<T?> Function() action) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      return await action();
    } catch (error) {
      NeonHttp.log('ReferralRepository.$label failed', error: error);
      return null;
    }
  }
}
