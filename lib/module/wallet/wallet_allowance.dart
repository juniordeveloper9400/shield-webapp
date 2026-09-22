import 'dart:math' as math;

/// Replay the ledger oldest first: commission is spent before plan allowance.
/// Counting all earlier plan debits prevents carry-forward being spent twice.
int planDebitsThrough(
  Iterable<({String kind, int amount, DateTime occurredOn})> entries,
  DateTime asOf, {
  DateTime? since,
}) {
  var earnings = 0;
  var spent = 0;
  for (final entry in entries) {
    if (entry.occurredOn.isAfter(asOf)) continue;
    if (entry.amount > 0 &&
        (entry.kind == 'REFERRAL_EARNINGS' || entry.kind == 'AGENT_EARNINGS')) {
      earnings += entry.amount;
    } else if (entry.amount < 0) {
      final fromEarnings = math.min(earnings, -entry.amount);
      earnings -= fromEarnings;
      if (since == null || !entry.occurredOn.isBefore(since)) {
        spent += -entry.amount - fromEarnings;
      }
    }
  }
  return spent;
}
