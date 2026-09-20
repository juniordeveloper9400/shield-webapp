import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/refer/referral_level.dart';
import 'package:shield/module/rewards/rewards_screen.dart';
import 'package:shield/module/rewards/rewards_service.dart';

/// 100 reward points are worth ₹1 — everywhere a point is turned into money.
void main() {
  setUp(() {
    RewardsService.instance.debugReset();
  });
  tearDown(() {
    RewardsService.instance.debugReset();
  });

  group('the exchange rate', () {
    test('is 100 points to the rupee', () {
      expect(RewardsService.pointsPerRupee, 100);
      expect(RewardsScreen.pointsPerRupee, 100);
      expect(RewardsScreen.rateLabel, '100 = ₹1');
    });

    test('turns points into whole rupees, rounding down', () {
      expect(RewardsService.rupeesForPoints(0), 0);
      expect(RewardsService.rupeesForPoints(99), 0);
      expect(RewardsService.rupeesForPoints(100), 1);
      expect(RewardsService.rupeesForPoints(250), 2);
      expect(RewardsService.rupeesForPoints(5300), 53);
      expect(RewardsService.rupeesForPoints(-100), 0);
    });

    test('keeps the points that do not yet make a rupee', () {
      expect(RewardsService.wholeRupeePoints(99), 0);
      expect(RewardsService.wholeRupeePoints(250), 200);
      expect(RewardsService.wholeRupeePoints(300), 300);
    });

    test('the screen quotes the same rate to the paisa', () {
      expect(RewardsScreen.rupeesFor(100), '1.00');
      expect(RewardsScreen.rupeesFor(250), '2.50');
      expect(RewardsScreen.rupeesFor(5), '0.05');
      expect(RewardsScreen.wholeRupeesFor(250), 2);
    });
  });

  group('the ladder pays points by level, worth rupees at that rate', () {
    test('each rung pays its own points', () {
      expect(ReferralLadder.levels.map((l) => l.points), [
        100,
        200,
        500,
        1500,
        3000,
      ]);
      expect(ReferralLadder.levels.map((l) => l.referralsRequired), [
        2,
        5,
        10,
        20,
        40,
      ]);
    });

    test('a member is paid for the rungs cleared and no others', () {
      int paid(int referrals) => ReferralLadder.pointsEarnedBy(
        ReferralProgress(directReferrals: referrals),
      );

      expect(paid(0), 0);
      expect(paid(1), 0); // Starter needs two
      expect(paid(2), 100);
      expect(paid(4), 100);
      expect(paid(5), 300); // Starter + Riser
      expect(paid(10), 800); // + Achiever
      expect(paid(20), 2300); // + Champion
      expect(paid(40), 5300); // the whole ladder
      expect(paid(400), 5300); // and nothing past it
    });

    test('and what those points are worth in rupees', () {
      int rupees(int referrals) => RewardsService.rupeesForPoints(
        ReferralLadder.pointsEarnedBy(
          ReferralProgress(directReferrals: referrals),
        ),
      );

      expect(rupees(2), 1); // Starter: 100 points = ₹1
      expect(rupees(5), 3);
      expect(rupees(10), 8);
      expect(rupees(40), 53); // clearing Legend: 5,300 points = ₹53
    });
  });

  group('the Rewards screen', () {
    testWidgets('states the rate and prices the balance at it', (tester) async {
      tester.view.physicalSize = const Size(400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      RewardsService.instance.debugSet(500);

      await tester.pumpWidget(const MaterialApp(home: RewardsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('100 = ₹1'), findsOneWidget);
      expect(find.text('₹5.00 off'), findsOneWidget); // 500 points
      expect(find.text('₹5.00'), findsOneWidget); // the hero figure
    });
  });
}
