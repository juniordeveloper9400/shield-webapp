import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/privilege/privilege_tier.dart';
import 'package:shield/module/wallet/wallet_service.dart';
import 'package:shield/module/wallet/wallet_allowance.dart';

void main() {
  final load = PrivilegeProgramme.loadFor(10000)!;
  final card = WalletCard(load: load, issuedOn: DateTime(2026, 8, 15), rechargedOn: DateTime(2026, 8, 15));
  test('unused allowance remains before next due day and accumulates on due day', () {
    expect(card.releasedBy(DateTime(2026, 8, 14)), 0);
    expect(card.releasedBy(DateTime(2026, 8, 15)), 916);
    expect(card.releasedBy(DateTime(2026, 9, 14)), 916);
    expect(card.releasedBy(DateTime(2026, 9, 15)), 1832);
    expect(card.releasedBy(DateTime(2026, 11, 15)), 3664);
  });
  test('prior plan spending is deducted once; commission spending is separate', () {
    final entries = [
      (kind: 'SPEND', amount: -400, occurredOn: DateTime(2026, 8, 20)),
      (kind: 'REFERRAL_EARNINGS', amount: 200, occurredOn: DateTime(2026, 9, 1)),
      (kind: 'SPEND', amount: -300, occurredOn: DateTime(2026, 9, 16)),
    ];
    final date = DateTime(2026, 9, 20);
    expect(planDebitsThrough(entries, date), 500);
    expect(card.releasedBy(date) - planDebitsThrough(entries, date), 1332);
  });
  test('releases stop after 12 instalments without losing unused allowance', () {
    expect(card.releasedBy(DateTime(2027, 7, 15)), 10992);
    expect(card.releasedBy(DateTime(2028, 8, 15)), 10992);
  });
  test('31st release is clamped to February; no early next-month release', () {
    final endMonth = WalletCard(load: load, issuedOn: DateTime(2026, 1, 31), rechargedOn: DateTime(2026, 1, 31));
    expect(endMonth.releasedBy(DateTime(2026, 2, 27)), 916);
    expect(endMonth.releasedBy(DateTime(2026, 2, 28)), 1832);
    expect(endMonth.releasedBy(DateTime(2026, 3, 1)), 1832);
  });
  test('wallet includes unused prior months and respects actual balance', () {
    final wallet = WalletService.instance;
    wallet.reset();
    wallet.activate(load, on: DateTime(2026, 8, 15));
    expect(wallet.availableAllowanceOn(DateTime(2026, 9, 15)), 1832);
    wallet.reset();
  });
}
