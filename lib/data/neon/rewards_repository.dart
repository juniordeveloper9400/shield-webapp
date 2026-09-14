import 'neon_http.dart';

/// `credit` only — the read side (`balanceFor`/`historyFor`) and redemption
/// have moved to `lib/data/backend/rewards_repository.dart`, backed by
/// `backend/api`'s `/v1/member/rewards/*` routes.
///
/// This one method stays on Neon because the backend has no endpoint for
/// crediting points at all — no registration bonus, no per-order points, no
/// referral bonus. `RewardsService.awardRegistrationBonus` /
/// `.awardForOrder` / `.awardForReferral` still call this directly.
///
/// The ledger *is* the balance — `balance = SUM(points)` — so appending a
/// row here is the only write; `app.users.reward_points` is resynced by the
/// same call so the admin console (which reads that column) stays in step.
///
/// Best-effort, like the other Neon repositories: with no `DATABASE_URL`
/// compiled in or the network down, the call no-ops.
class RewardsRepository {
  const RewardsRepository._();

  static const RewardsRepository instance = RewardsRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// Appends a ledger row of [points] (signed) for [phone] with [reason], and
  /// moves `app.users.reward_points` by the same amount. Inserts a minimal
  /// `app.users` row first if sign-in has not written one yet.
  ///
  /// With [once] set, the row is written only when no earlier row for this
  /// member already carries [reason] — this is how the one-time registration
  /// bonus stays one-time.
  ///
  /// Returns the row's points on success, or `null` when nothing was written
  /// (database off, a once-only reason already credited, or an error).
  Future<int?> credit({
    required String phone,
    required String name,
    required int points,
    required String reason,
    String note = '',
    String? refType,
    int? refId,
    bool once = false,
  }) async {
    if (!NeonHttp.isConfigured || points == 0) {
      return null;
    }
    try {
      // 1. Make sure the member row exists, then append the ledger row —
      //    skipped entirely when `once` is set and this reason is already on
      //    the ledger. `member` only touches `app.users`; the RETURNING comes
      //    from the ledger insert, a different table, so nothing clashes.
      final inserted = await NeonHttp.instance.query(
        r'''
          WITH member AS (
            INSERT INTO app.users (phone, name)
            VALUES ($1, $2)
            ON CONFLICT (phone) DO UPDATE SET updated_at = now()
            RETURNING id
          )
          INSERT INTO app.reward_point_transaction
            (member_id, points, reason, ref_type, ref_id, note)
          SELECT member.id, $3, $4::app.reward_txn_reason, $5, $6, $7
          FROM member
          WHERE ($8 <> 'once') OR NOT EXISTS (
            SELECT 1 FROM app.reward_point_transaction x
            WHERE x.member_id = member.id
              AND x.reason = $4::app.reward_txn_reason
          )
          RETURNING points
        ''',
        [phone, name, points, reason, refType, refId, note, once ? 'once' : ''],
      );
      if (inserted.isEmpty) {
        return null;
      }

      // 2. Resync the denormalised cache from the ledger. A recompute rather
      //    than an increment, so the column is self-healing if it ever drifts.
      await NeonHttp.instance.query(
        r'''
          UPDATE app.users u
          SET reward_points = greatest(0, coalesce((
                SELECT sum(t.points)
                FROM app.reward_point_transaction t
                WHERE t.member_id = u.id
              ), 0)),
              updated_at = now()
          WHERE u.phone = $1
        ''',
        [phone],
      );

      NeonHttp.log('RewardsRepository.credit: $reason $points for $phone');
      return int.tryParse((inserted.first['points'] ?? '').toString());
    } catch (error) {
      NeonHttp.log('RewardsRepository.credit($reason) failed', error: error);
      return null;
    }
  }
}
