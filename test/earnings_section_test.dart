import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/money.dart';
import 'package:shield/module/earnings/earnings_detail_screen.dart';
import 'package:shield/module/earnings/member_earnings.dart';
import 'package:shield/module/home/earnings_section.dart';
import 'package:shield/module/orders/orders_screen.dart';
import 'package:shield/module/orders/purchase_service.dart';
import 'package:shield/module/privilege/privilege_card.dart';
import 'package:shield/module/privilege/privilege_tier.dart';
import 'package:shield/module/wallet/wallet_service.dart';
import 'package:shield/screens/home_screen.dart';

void main() {
  void resetAll() {
    PurchaseService.instance.clear();
    PurchaseService.instance.seedSampleOrders();
    WalletService.instance.reset();
  }

  setUp(resetAll);
  tearDown(resetAll);

  Future<void> pumpSection(
    WidgetTester tester, {
    Size size = const Size(400, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: EarningsSection())),
    );
    await tester.pumpAndSettle();
  }

  group('what a purchase earns', () {
    test('the saving is the gap between the printed price and the bill', () {
      // The whole rule: listed at ₹500, bought for ₹450, earned ₹50. Note:
      // this is Purchase.saved itself, still around for whatever else reads
      // it — "Your earnings" no longer does (see the group below).
      const purchase = Purchase(
        id: 'SHD-1',
        placedOn: '01 Aug 2026',
        itemCount: 1,
        mrpTotal: 500,
        paidTotal: 450,
        status: OrderStatus.delivered,
      );

      expect(purchase.saved, 50);
      expect(purchase.savedLabel, '₹50');
      expect(purchase.paidLabel, '₹450');
      expect(purchase.mrpLabel, '₹500');
    });

    test('an order that cost list price earned nothing, not less', () {
      const noDiscount = Purchase(
        id: 'SHD-2',
        placedOn: '01 Aug 2026',
        itemCount: 1,
        mrpTotal: 500,
        paidTotal: 500,
        status: OrderStatus.delivered,
      );
      expect(noDiscount.saved, 0);

      // Never negative: an order that somehow cost more than list price did
      // not earn a negative amount, it earned nothing.
      const overpaid = Purchase(
        id: 'SHD-3',
        placedOn: '01 Aug 2026',
        itemCount: 1,
        mrpTotal: 400,
        paidTotal: 450,
        status: OrderStatus.delivered,
      );
      expect(overpaid.saved, 0);
    });

    test('the totals are added up from the orders, not stored', () {
      final orders = PurchaseService.instance;

      final counted = orders.purchases.where((order) => order.status.counts);
      expect(
        orders.savedTotal,
        counted.fold<int>(0, (sum, order) => sum + order.saved),
      );
      expect(
        orders.paidTotal,
        counted.fold<int>(0, (sum, order) => sum + order.paidTotal),
      );
      expect(orders.savedTotal, orders.mrpTotal - orders.paidTotal);
    });

    test('a cancelled order is listed but earns nothing', () {
      final orders = PurchaseService.instance;
      final cancelled = orders.purchases.firstWhere(
        (order) => order.status == OrderStatus.cancelled,
      );

      // It is still in the book the member can scroll.
      expect(orders.purchases, contains(cancelled));
      // It was never paid for, so it cannot have saved anything.
      expect(cancelled.status.counts, isFalse);
      expect(orders.savedTotal, isNot(contains(cancelled.saved)));
      expect(
        orders.mrpTotal,
        orders.purchases.fold<int>(0, (sum, order) => sum + order.mrpTotal) -
            cancelled.mrpTotal,
      );
    });

    test('the percentage is taken over the totals, not averaged', () {
      final orders = PurchaseService.instance;

      // A 40% saving on ₹100 and a 5% saving on ₹5,000 do not average to
      // 22.5% of anything a member spent.
      expect(
        orders.savedFraction,
        closeTo(orders.savedTotal / orders.mrpTotal, 0.0001),
      );
    });

    test('an empty book earns nothing and divides by nothing', () {
      PurchaseService.instance.clear();

      expect(PurchaseService.instance.savedTotal, 0);
      expect(PurchaseService.instance.savedFraction, 0);
      expect(PurchaseService.instance.savedPercentLabel, '0%');
    });

    test('active orders are the ones still on their way', () {
      // Delivered is done and cancelled never happened.
      expect(PurchaseService.instance.activeCount, 2);
    });
  });

  group('your earnings on home', () {
    testWidgets(
      'with no bill discount on any order yet, shows the zero-state',
      (tester) async {
        // seedSampleOrders() carries no bill data at all — none of these
        // orders has actually been discounted at billing time, so there is
        // nothing to show yet under the bill-discount model.
        await pumpSection(tester);

        expect(find.text('Your savings'), findsOneWidget);
        // A plain-language label spells out what the big figure is, so it is
        // not mistaken for a spendable balance.
        expect(find.text('Total money you have saved'), findsOneWidget);
        expect(
          find.text('Buy at Sahakar 360 prices and the difference is yours.'),
          findsOneWidget,
        );
        expect(find.text('₹0'), findsOneWidget);

        // Sub-tiles and Your orders button are NOT on the home card.
        expect(find.text('Total price'), findsNothing);
        expect(find.text('You paid'), findsNothing);
        expect(find.text('You saved'), findsNothing);
        expect(find.text('Your orders'), findsNothing);
      },
    );

    testWidgets(
      'shows only total earnings and no order button or sub-tiles, once a bill is discounted',
      (tester) async {
        // The same order the store actually gave ₹438 off — a real bill
        // discount, not just a gap between mrpTotal and paidTotal.
        PurchaseService.instance.updateOne(
          _billedOrder(id: 'SHD-100482', billAmount: 1248, billDiscount: 438),
        );
        await pumpSection(tester);

        expect(find.text('Your savings'), findsOneWidget);
        expect(find.text('Total money you have saved'), findsOneWidget);
        expect(
          find.text('₹${formatRupees(MemberEarnings.saved)}'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Kept out of ₹${formatRupees(MemberEarnings.totalPrice)} of total price.',
          ),
          findsOneWidget,
        );

        // Sub-tiles and Your orders button are NOT on the home card.
        expect(find.text('Total price'), findsNothing);
        expect(find.text('You paid'), findsNothing);
        expect(find.text('You saved'), findsNothing);
        expect(find.text('Your orders'), findsNothing);
      },
    );

    testWidgets('tapping opens the dedicated earnings detail screen', (tester) async {
      await pumpSection(tester);

      await tester.tap(find.byType(EarningsSection));
      await tester.pumpAndSettle();

      expect(find.byType(EarningsDetailScreen), findsOneWidget);
      expect(find.text('Your Earnings'), findsOneWidget);
      // The three stat tiles below the hero card, same as "Earnings Breakdown
      // by Order" and "Health Pass Plan Bonus" — this app's own detail
      // screen has no separate "Your Savings" section heading above them,
      // unlike the root app's.
      expect(find.text('Total price'), findsOneWidget);
      expect(find.text('You paid'), findsOneWidget);
      expect(find.text('You saved'), findsOneWidget);
      expect(find.text('Earnings Breakdown by Order'), findsOneWidget);
      // No plan has been activated, so there is nothing to show here.
      expect(find.text('Health Pass Plan Bonus'), findsNothing);

      // Does not show the Your orders button on the details page either.
      expect(find.text('Your orders'), findsNothing);
    });

    testWidgets(
      'the breakdown list shows only the order that actually got a bill discount',
      (tester) async {
        final discounted = _billedOrder(
          id: 'SHD-100482',
          billAmount: 1248,
          billDiscount: 438,
        );
        PurchaseService.instance.updateOne(discounted);
        final undiscounted = PurchaseService.instance.purchases.firstWhere(
          (o) => o.id == 'SHD-100461',
        );

        await pumpSection(tester);
        await tester.tap(find.byType(EarningsSection));
        await tester.pumpAndSettle();

        expect(find.text(discounted.id), findsOneWidget);
        expect(find.text('+${discounted.billDiscountLabel}'), findsOneWidget);
        expect(find.text('Bill ${discounted.billGrossLabel}'), findsOneWidget);
        expect(find.text('Paid ${discounted.billPaidLabel}'), findsOneWidget);

        // Never billed with a discount — not in this list at all, even
        // though seedSampleOrders gave it its own mrpTotal/paidTotal gap.
        expect(find.text(undiscounted.id), findsNothing);
      },
    );

    testWidgets('referral figures are not in this total', (tester) async {
      await pumpSection(tester);

      expect(find.text('Sahakar'), findsNothing);
      expect(find.text('Points'), findsNothing);
      expect(find.textContaining('pts'), findsNothing);
      expect(find.textContaining('invites'), findsNothing);
    });

    testWidgets(
      'activating a privilege plan folds its 10% bonus into the total, on top of any bill discount',
      (tester) async {
        // A real bill discount on top of the plan bonus — not instead of it.
        PurchaseService.instance.updateOne(
          _billedOrder(id: 'SHD-100482', billAmount: 1248, billDiscount: 438),
        );
        final ordersOnly = MemberEarnings.saved;
        final silver = PrivilegeProgramme.silver.entry;
        WalletService.instance.activate(silver);

        await pumpSection(tester);

        // ₹1,000 on a ₹10,000 Silver load — on top of what the bill discount
        // alone already saved, not instead of it.
        expect(ordersOnly, 438);
        expect(silver.bonus, 1000);
        expect(
          find.text('₹${formatRupees(ordersOnly + silver.bonus)}'),
          findsOneWidget,
        );

        await tester.tap(find.byType(EarningsSection));
        await tester.pumpAndSettle();

        expect(find.text('Health Pass Plan Bonus'), findsOneWidget);
        expect(find.text(silver.name), findsOneWidget);
        expect(find.text('+${silver.bonusLabel}'), findsOneWidget);
      },
    );

    testWidgets(
      'placing a plain order does not move the total — there is no bill yet',
      (tester) async {
        await pumpSection(tester);
        final before = MemberEarnings.saved;

        PurchaseService.instance.record(
          id: 'SHD-100500',
          placedOn: '27 Aug 2026',
          itemCount: 2,
          mrpTotal: 500,
          paidTotal: 450,
        );
        await tester.pumpAndSettle();

        expect(MemberEarnings.saved, before);
        expect(find.text('₹${_grouped(before)}'), findsOneWidget);
      },
    );

    testWidgets(
      'the total moves once that order is actually billed with a discount',
      (tester) async {
        final order = PurchaseService.instance.record(
          id: 'SHD-100501',
          placedOn: '27 Aug 2026',
          itemCount: 2,
          mrpTotal: 500,
          paidTotal: 450,
        );
        await pumpSection(tester);
        final before = MemberEarnings.saved;

        PurchaseService.instance.updateOne(
          _billedOrder(id: order.id, billAmount: 450, billDiscount: 50),
        );
        await tester.pumpAndSettle();

        expect(MemberEarnings.saved, before + 50);
        expect(find.text('₹${_grouped(before + 50)}'), findsOneWidget);
      },
    );

    testWidgets('a member who has bought nothing is told how to start', (
      tester,
    ) async {
      PurchaseService.instance.clear();
      await pumpSection(tester);

      expect(
        find.text('Buy at Sahakar 360 prices and the difference is yours.'),
        findsOneWidget,
      );
      expect(find.textContaining('Kept out of'), findsNothing);
      expect(find.text('₹0'), findsOneWidget);
    });

    testWidgets('sits under the privilege card on the home screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 7000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: HomeScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EarningsSection), findsOneWidget);

      // Not asserting its position against ReferEarnCard here — that card
      // sits behind its own ReferEarnGate eligibility check, not something
      // this default test setup satisfies, and that gate is a separate
      // concern from this earnings-model change.
      final privilege = tester.getTopLeft(find.byType(PrivilegeCard)).dy;
      final earnings = tester.getTopLeft(find.byType(EarningsSection)).dy;

      expect(earnings, greaterThan(privilege));
    });
  });

  group('the orders screen reads the same book', () {
    testWidgets(
      'lists every order, with no "Saved" badge — seedSampleOrders carries '
      'no bill discount, only an mrpTotal/paidTotal gap',
      (tester) async {
        tester.view.physicalSize = const Size(400, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(const MaterialApp(home: OrdersScreen()));
        await tester.pumpAndSettle();

        for (final order in PurchaseService.instance.purchases) {
          expect(find.text(order.id), findsOneWidget, reason: order.id);
        }

        // None of these orders has actually been discounted at billing
        // time, so the badge — gated on Purchase.billDiscount, never the
        // checkout-time mrpTotal/paidTotal gap — shows on none of them.
        expect(find.textContaining('Saved ₹'), findsNothing);
      },
    );

    testWidgets(
      'shows "Saved" only for an order the store actually billed with a '
      'discount, reading the real figure, not the printed-price gap',
      (tester) async {
        tester.view.physicalSize = const Size(400, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // mrpTotal 1686 / paidTotal 1248 would gap ₹438 on its own — give it
        // a different, real bill discount instead, so a test that passed by
        // coincidence (the two figures matching) can't hide this not
        // actually reading billDiscount.
        final discounted = _billedOrder(
          id: 'SHD-100482',
          billAmount: 1248,
          billDiscount: 300,
        );
        PurchaseService.instance.updateOne(discounted);

        await tester.pumpWidget(const MaterialApp(home: OrdersScreen()));
        await tester.pumpAndSettle();

        expect(find.text('Saved ${discounted.billDiscountLabel}'), findsOneWidget);
        expect(find.text('Saved ₹438'), findsNothing);

        // Every other order (including the cancelled one) still carries no
        // bill discount, so still no badge for any of them.
        expect(find.textContaining('Saved ₹'), findsOneWidget);
      },
    );
  });
}

/// A delivered order the store actually gave a real bill discount on — the
/// only shape "Your earnings" counts at all now, per [Purchase.billDiscount]'s
/// own doc. [id] lets a test either add a fresh one or, via [PurchaseService.
/// updateOne], swap in a billed version of an order already on file.
Purchase _billedOrder({
  required String id,
  required int billAmount,
  required int billDiscount,
}) => Purchase(
  id: id,
  placedOn: '20 Aug 2026',
  itemCount: 1,
  mrpTotal: 0,
  paidTotal: 0,
  status: OrderStatus.delivered,
  billAmount: billAmount,
  billDiscount: billDiscount,
);

/// Indian digit grouping, so the expectations read as the screen prints them.
String _grouped(int amount) {
  final digits = amount.toString();
  if (digits.length <= 3) {
    return digits;
  }
  final tail = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) {
    groups.insert(0, rest);
  }
  return '${groups.join(',')},$tail';
}
