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

  test('Redeemable shows carry-forward even before the card\'s next due day', () {
    final wallet = WalletService.instance;
    wallet.reset();
    wallet.activate(load, on: DateTime(2026, 8, 15));
    // Before this fix, Redeemable asked "has a FRESH twelfth opened up
    // today" (monthlyRedeemableOn, still correct for its own purpose) — 03
    // Oct falls between the Sep 15 and Oct 15 instalments, so that
    // question's answer is "no, nothing new yet" and the card read ₹0
    // redeemable despite the Aug/Sep instalments (₹1,832) never having been
    // touched.
    expect(
      wallet.monthlyRedeemableOn(DateTime(2026, 10, 3)),
      0,
      reason: "the narrower question this isn't answering any more",
    );
    expect(wallet.redeemableAllowanceOn(DateTime(2026, 10, 3)), 2748); // Aug + Sep carry-forward + October's own twelfth, counted from the 1st
    wallet.reset();
  });

  test("Redeemable is the whole month's allowance and stays put; Available moves with orders", () {
    final wallet = WalletService.instance;
    wallet.reset();
    final now = DateTime.now();
    // A plan taken two months ago, on the 1st: its day has come round, so the
    // three twelfths (two carried forward + this month's) are all counted.
    wallet.activate(load, on: DateTime(now.year, now.month - 2, 1));
    expect(wallet.redeemableAllowanceOn(now), 2748);
    expect(wallet.availableAllowanceOn(now), 2748);

    // An order this month comes off Available only — Redeemable is static.
    wallet.spend(amount: 800, label: 'Order');
    expect(wallet.redeemedThisMonth, 800);
    final after = DateTime.now(); // the order is dated now, so ask as of after it
    expect(wallet.redeemableAllowanceOn(after), 2748);
    expect(wallet.availableAllowanceOn(after), 1948);
    wallet.reset();
  });

  test("this month's twelfth counts from the 1st, before the card's own day", () {
    // Issued on the 25th: the old per-due-day rule gave 0 on the 24th of the
    // next month for the fresh twelfth; the month rule counts it from the 1st.
    final late = WalletCard(
      load: load,
      issuedOn: DateTime(2026, 8, 25),
      rechargedOn: DateTime(2026, 8, 25),
    );
    expect(late.releasedThroughMonthOf(DateTime(2026, 8, 25)), 916);
    expect(late.releasedThroughMonthOf(DateTime(2026, 9, 1)), 1832);
    expect(late.releasedThroughMonthOf(DateTime(2026, 9, 24)), 1832);
    expect(late.releasedBy(DateTime(2026, 9, 24)), 916, reason: 'unchanged');
    expect(late.releasedThroughMonthOf(DateTime(2026, 8, 1)), 0);
    expect(late.releasedThroughMonthOf(DateTime(2030, 1, 1)), 10992);
  });
}
