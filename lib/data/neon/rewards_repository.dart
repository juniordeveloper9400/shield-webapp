import 'neon_http.dart';

/// One line of the reward-points ledger: a signed amount, why it moved, and
/// when. `points` is negative for a redemption.
class RewardTxn {
  final int points;

  /// An `app.reward_txn_reason` value —
  /// `REGISTRATION` / `ORDER` / `REFERRAL_LEVEL` / `REDEMPTION` / `ADJUSTMENT`.
  final String reason;
  final String note;
  final DateTime at;

  const RewardTxn({
    required this.points,
    required this.reason,
    required this.note,
    required this.at,
  });

  bool get isCredit => points >= 0;
}

/// Reads and writes `app.reward_point_transaction` on Neon over the HTTP SQL
/// endpoint (see [NeonHttp]).
///
/// The ledger *is* the balance — `balance = SUM(points)` — so there is no
/// separate "set the balance" call, only [credit], which appends a row.
/// `app.users.reward_points` is moved by the same amount so the admin console
/// (which reads that column) stays in step.
///
/// Best-effort, like the other Neon repositories: with no `DATABASE_URL`
/// compiled in or the network down, reads return `null` (not `0`) and writes
/// no-op. The same code path runs on the APK and the web build.
class RewardsRepository {
  const RewardsRepository._();

  static const RewardsRepository instance = RewardsRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// The member's current balance — the signed sum of every ledger row for
  /// [phone]. `null` when the database is off or unreachable, so a transient
  /// failure is not shown as an emptied balance.
  Future<int?> balanceFor(String phone) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await NeonHttp.instance.query(
        r'''
          SELECT coalesce(sum(t.points), 0) AS balance
          FROM app.reward_point_transaction t
          JOIN app.users u ON u.id = t.member_id
          WHERE u.phone = $1
        ''',
        [phone],
      );
      final value = rows.isEmpty ? '0' : (rows.first['balance'] ?? '0');
      return int.tryParse(value.toString()) ?? 0;
    } catch (error) {
      NeonHttp.log('RewardsRepository.balanceFor failed', error: error);
      return null;
    }
  }

  /// The most recent ledger lines for [phone], newest first. `null` on a
  /// failed read.
  Future<List<RewardTxn>?> historyFor(String phone, {int limit = 50}) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await NeonHttp.instance.query(
        r'''
          SELECT t.points,
                 t.reason::text        AS reason,
                 coalesce(t.note, '')  AS note,
                 t.created_at
          FROM app.reward_point_transaction t
          JOIN app.users u ON u.id = t.member_id
          WHERE u.phone = $1
          ORDER BY t.created_at DESC
          LIMIT $2
        ''',
        [phone, limit],
      );
      return rows.map((row) {
        return RewardTxn(
          points: int.tryParse((row['points'] ?? '0').toString()) ?? 0,
          reason: (row['reason'] ?? '').toString(),
          note: (row['note'] ?? '').toString(),
          at: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0),
        );
      }).toList(growable: false);
    } catch (error) {
      NeonHttp.log('RewardsRepository.historyFor failed', error: error);
      return null;
    }
  }

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
