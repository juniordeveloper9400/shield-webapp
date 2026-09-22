import 'package:flutter_test/flutter_test.dart';
import '../lib/module/agent/withdrawal_policy.dart';

void main() {
  test('withdrawal is zero below 3000 and available from exactly 3000', () {
    for (final earned in [0, 500, 2999]) {
      expect(
        eligibleWithdrawalAmount(earned: earned, redeemed: 0, pending: 0),
        0,
      );
    }
    expect(
      eligibleWithdrawalAmount(earned: 3000, redeemed: 0, pending: 0),
      3000,
    );
    expect(
      eligibleWithdrawalAmount(earned: 4500, redeemed: 0, pending: 0),
      4500,
    );
  });
  test('paid and pending withdrawals cannot be withdrawn again', () {
    expect(
      eligibleWithdrawalAmount(earned: 8000, redeemed: 3000, pending: 3000),
      0,
    );
    expect(
      eligibleWithdrawalAmount(earned: 9000, redeemed: 3000, pending: 3000),
      3000,
    );
    expect(
      eligibleWithdrawalAmount(earned: 1000, redeemed: 2000, pending: 0),
      0,
    );
  });
}
