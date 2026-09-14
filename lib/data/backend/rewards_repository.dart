import 'dart:math';

import 'backend_http.dart';

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

/// Reads the reward-points ledger and redeems points into the wallet through
/// `backend/api` — `GET /v1/member/rewards/transactions` and
/// `POST /v1/member/rewards/redeem` (see `rewards.service.ts`).
///
/// Crediting points (registration bonus, per-order points, referral reward)
/// has no backend endpoint yet — those stay on
/// `lib/data/neon/rewards_repository.dart`'s `credit` for now. This class
/// only covers the read side plus redemption, which the backend already
/// does atomically (debits the points ledger *and* credits the wallet
/// balance in one transaction) — a real correctness improvement over the
/// old flow's two separate client-driven writes.
///
/// Best-effort, like the other backend repositories: an unconfigured
/// backend or the network down makes reads return `null` (not `0`) and
/// [redeem] return `false`.
class RewardsRepository {
  const RewardsRepository._();

  static const RewardsRepository instance = RewardsRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// The member's current balance — summed from the ledger client-side
  /// (matching the old "the ledger is the balance" principle) rather than
  /// trusting a cached field. `null` when the backend is off or unreachable.
  Future<int?> balanceFor() async {
    final history = await historyFor();
    if (history == null) {
      return null;
    }
    return history.fold<int>(0, (sum, txn) => sum + txn.points);
  }

  /// The most recent ledger lines for the signed-in member, newest first —
  /// `null` on a failed read. [limit] is accepted for parity with the old
  /// direct-Neon signature; the backend returns the member's full history
  /// with no paging today.
  Future<List<RewardTxn>?> historyFor({int limit = 50}) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request('GET', '/v1/member/rewards/transactions')
          as List<dynamic>;
      return rows.cast<Map<String, dynamic>>().take(limit).map((row) {
        return RewardTxn(
          points: _int(row['points']),
          reason: (row['reason'] ?? '').toString(),
          note: (row['note'] ?? '').toString(),
          at: DateTime.tryParse((row['createdAt'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0),
        );
      }).toList(growable: false);
    } catch (error) {
      BackendHttp.log('RewardsRepository.historyFor failed', error: error);
      return null;
    }
  }

  /// Spends [points] into the wallet balance — one backend call does both
  /// the points-ledger debit and the wallet credit, atomically. Returns
  /// `true` on success.
  Future<bool> redeem(int points) async {
    if (!BackendHttp.isConfigured || points <= 0) {
      return false;
    }
    try {
      await BackendHttp.instance.request(
        'POST',
        '/v1/member/rewards/redeem',
        body: {'points': points},
        headers: {'Idempotency-Key': _newIdempotencyKey()},
      );
      return true;
    } catch (error) {
      BackendHttp.log('RewardsRepository.redeem failed', error: error);
      return false;
    }
  }

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// A fresh random v4-shaped UUID, generated fresh for every [redeem] call
  /// — this method does not retry on failure, so there is no case here
  /// needing the same key resent. High-entropy by construction: the
  /// backend's uniqueness constraint on this key is global per endpoint,
  /// not per-session, so it must never be derived from anything
  /// low-entropy like a timestamp.
  static String _newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    String hex(int start, int end) =>
        bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
