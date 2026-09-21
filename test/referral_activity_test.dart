import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/referral_repository.dart';
import 'package:shield/module/refer/journey_map.dart';
import 'package:shield/module/refer/refer_earn_screen.dart';
import 'package:shield/module/refer/referral_level.dart';
import 'package:shield/module/refer/referral_service.dart';
import 'package:shield/module/refer/reward_graph.dart';

/// What the referrer sees of the people they referred: somebody joining shows
/// up straight away, then moves across as they transact and take a plan.
void main() {
  group('the stages a referred person passes through', () {
    test(
      'reads the database status, ignoring an invite that was only shared',
      () {
        expect(ReferredStage.fromStatus('REGISTERED'), ReferredStage.joined);
        expect(
          ReferredStage.fromStatus('TRANSACTED'),
          ReferredStage.transacted,
        );
        expect(
          ReferredStage.fromStatus('PLAN_ACTIVATED'),
          ReferredStage.planActivated,
        );
        expect(ReferredStage.fromStatus('registered'), ReferredStage.joined);
        expect(ReferredStage.fromStatus('SHARED'), isNull);
        expect(ReferredStage.fromStatus(null), isNull);
      },
    );

    test('a name is cut down to first name and last initial', () {
      expect(ReferredMember.shortName('Nihal'), 'Nihal');
      expect(ReferredMember.shortName('Althaf Muhammed'), 'Althaf M.');
      expect(ReferredMember.shortName('  Anu   k  Nair '), 'Anu N.');
      expect(ReferredMember.shortName(''), 'A friend');
      expect(ReferredMember.shortName(null), 'A friend');
    });

    test('the date beside a person is the last thing they did', () {
      final joined = DateTime(2026, 9, 1);
      final paid = DateTime(2026, 9, 5);
      final plan = DateTime(2026, 9, 9);

      expect(
        ReferredMember(
          name: 'A',
          stage: ReferredStage.joined,
          joinedAt: joined,
        ).lastActivityAt,
        joined,
      );
      expect(
        ReferredMember(
          name: 'A',
          stage: ReferredStage.transacted,
          joinedAt: joined,
          transactedAt: paid,
        ).lastActivityAt,
        paid,
      );
      expect(
        ReferredMember(
          name: 'A',
          stage: ReferredStage.planActivated,
          joinedAt: joined,
          transactedAt: paid,
          planActivatedAt: plan,
        ).lastActivityAt,
        plan,
      );
    });

    test('joined counts everyone; transacted only those who paid', () {
      const progress = ReferralProgress(
        directReferrals: 2,
        pendingReferrals: 3,
      );

      expect(progress.joinedReferrals, 5);
      // The ladder moves on transactions alone — a sign-up does not clear a rung.
      expect(progress.currentLevel(ReferralLadder.levels), 1);
      expect(
        const ReferralProgress(
          directReferrals: 0,
          pendingReferrals: 9,
        ).currentLevel(ReferralLadder.levels),
        0,
      );
    });
  });

  group('reading the people list the backend returns', () {
    test(
      'keeps the order, drops shared invites, and keeps the names as sent',
      () {
        final people = ReferralRepository.inviteesFrom([
          {
            'status': 'PLAN_ACTIVATED',
            'name': 'Althaf M.',
            'registeredAt': '2026-09-01T10:00:00.000Z',
            'transactedAt': '2026-09-02T10:00:00.000Z',
            'planActivatedAt': '2026-09-03T10:00:00.000Z',
          },
          {'status': 'SHARED', 'name': 'Ignored'},
          // A blank name reads as "A friend" — and that must not be re-shortened.
          {
            'status': 'REGISTERED',
            'name': '',
            'registeredAt': '2026-09-20T08:30:00.000Z',
          },
          {'status': 'TRANSACTED', 'name': 'A friend'},
        ]);

        expect(people.map((p) => p.name), [
          'Althaf M.',
          'A friend',
          'A friend',
        ]);
        expect(people.map((p) => p.stage), [
          ReferredStage.planActivated,
          ReferredStage.joined,
          ReferredStage.transacted,
        ]);
        expect(people[0].planActivatedAt, DateTime.utc(2026, 9, 3, 10));
        expect(people[1].joinedAt, DateTime.utc(2026, 9, 20, 8, 30));
        expect(people[2].transactedAt, isNull);
      },
    );
  });

  group('the refer & earn screen', () {
    Future<void> pump(
      WidgetTester tester,
      ReferralProgress progress, {
      String code = ReferralLadder.fallbackCode,
      Future<void> Function()? onRefresh,
      Size size = const Size(400, 3200),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: ReferEarnScreen(
            progress: progress,
            code: code,
            onRefresh: onRefresh,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openList(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('referred-list-toggle')));
      await tester.pumpAndSettle();
    }

    testWidgets('a friend who has only joined shows straight away', (
      tester,
    ) async {
      await pump(
        tester,
        ReferralProgress(
          directReferrals: 0,
          pendingReferrals: 1,
          invitees: [
            ReferredMember(
              name: 'Nihal K.',
              stage: ReferredStage.joined,
              joinedAt: DateTime(2026, 9, 21),
            ),
          ],
        ),
      );

      // Not the empty state the page used to be stuck on. The list is folded
      // to a line, and opens on a tap.
      expect(find.textContaining('Nobody has joined'), findsNothing);
      expect(find.text('People you referred'), findsOneWidget);
      expect(find.text('1 joined · 0 transacted'), findsOneWidget);
      expect(find.text('Nihal K.'), findsNothing);
      await openList(tester);
      expect(find.text('Nihal K.'), findsOneWidget);
      expect(
        find.textContaining('Waiting for their first order'),
        findsOneWidget,
      );
      // The card says why the level has not moved, and so does the rung.
      expect(find.textContaining('1 friend has joined'), findsOneWidget);
      expect(find.textContaining('1 joined — counts once'), findsOneWidget);
      // Joined 1, Transacted 0.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('standing-card')),
          matching: find.text('1'),
        ),
        findsWidgets,
      );
    });

    testWidgets('a friend who has transacted counts towards the level', (
      tester,
    ) async {
      await pump(
        tester,
        ReferralProgress(
          directReferrals: 2,
          plansActivated: 1,
          invitees: [
            ReferredMember(
              name: 'Althaf M.',
              stage: ReferredStage.planActivated,
              joinedAt: DateTime(2026, 9, 1),
              transactedAt: DateTime(2026, 9, 2),
              planActivatedAt: DateTime(2026, 9, 3),
            ),
            ReferredMember(
              name: 'Nihal K.',
              stage: ReferredStage.transacted,
              joinedAt: DateTime(2026, 9, 1),
              transactedAt: DateTime(2026, 9, 4),
            ),
          ],
        ),
      );

      expect(find.text('2 joined · 2 transacted · 1 plan'), findsOneWidget);
      await openList(tester);
      expect(find.text('Althaf M.'), findsOneWidget);
      expect(find.text('Plan activated'), findsOneWidget);
      expect(find.text('Made a transaction'), findsOneWidget);
      expect(find.textContaining('Counts towards your level'), findsOneWidget);
      // Nobody is waiting, so no "has joined" nudge.
      expect(
        find.byKey(const ValueKey('pending-referrals-note')),
        findsNothing,
      );
    });

    testWidgets('with nobody referred yet it says so', (tester) async {
      await pump(tester, const ReferralProgress(directReferrals: 0));

      expect(
        find.textContaining('Nobody has joined with your code'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pending-referrals-note')),
        findsNothing,
      );
    });

    testWidgets(
      'the code is not offered for sharing until it is the real one',
      (tester) async {
        await pump(
          tester,
          const ReferralProgress(directReferrals: 0),
          code: '',
        );

        expect(find.text('Getting your code…'), findsOneWidget);
        expect(find.text('SAHAKAR-RN4821'), findsNothing);
        final invite = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(invite.onPressed, isNull);
      },
    );

    testWidgets('a real code can be shared', (tester) async {
      await pump(tester, const ReferralProgress(directReferrals: 0));

      expect(find.text('SAHAKAR-RN4821'), findsOneWidget);
      final invite = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(invite.onPressed, isNotNull);
    });

    testWidgets('pulling the page down asks for a fresh reading', (
      tester,
    ) async {
      var refreshed = 0;
      await pump(
        tester,
        const ReferralProgress(directReferrals: 0),
        onRefresh: () async => refreshed++,
        // A phone-sized page: the pull distance a refresh needs scales with it.
        size: const Size(400, 800),
      );

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(refreshed, 1);
    });

    testWidgets('has no pull-to-refresh when nothing can be refreshed', (
      tester,
    ) async {
      await pump(tester, const ReferralProgress(directReferrals: 0));

      expect(find.byType(RefreshIndicator), findsNothing);
    });
  });

  group('the people list folds and unfolds', () {
    Future<void> pumpWith(WidgetTester tester, ReferralProgress progress) async {
      tester.view.physicalSize = const Size(400, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ReferEarnScreen(progress: progress)));
      await tester.pumpAndSettle();
    }

    List<ReferredMember> people(int count) => [
      for (var i = 1; i <= count; i++)
        ReferredMember(
          name: 'Friend$i',
          stage: ReferredStage.joined,
          joinedAt: DateTime(2026, 9, 1),
        ),
    ];

    testWidgets('starts folded to a summary, opens on a tap and folds again', (
      tester,
    ) async {
      await pumpWith(
        tester,
        ReferralProgress(
          directReferrals: 0,
          pendingReferrals: 2,
          invitees: people(2),
        ),
      );

      expect(find.text('2 joined · 0 transacted'), findsOneWidget);
      expect(find.text('Friend1'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('referred-list-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Friend1'), findsOneWidget);
      expect(find.text('Friend2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('referred-list-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Friend1'), findsNothing);
      // The summary is what is left, so the count is never hidden.
      expect(find.text('2 joined · 0 transacted'), findsOneWidget);
    });

    testWidgets('a long list opens five at a time', (tester) async {
      await pumpWith(
        tester,
        ReferralProgress(
          directReferrals: 0,
          pendingReferrals: 23,
          invitees: people(23),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('referred-list-toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Friend5'), findsOneWidget);
      expect(find.text('Friend6'), findsNothing);
      expect(find.text('Show more (18 left)'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('referred-list-more')));
      await tester.tap(find.byKey(const ValueKey('referred-list-more')));
      await tester.pumpAndSettle();
      expect(find.text('Friend15'), findsOneWidget);
      expect(find.text('Friend16'), findsNothing);
      expect(find.text('Show more (8 left)'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('referred-list-more')));
      await tester.tap(find.byKey(const ValueKey('referred-list-more')));
      await tester.pumpAndSettle();
      expect(find.text('Friend23'), findsOneWidget);
      expect(find.byKey(const ValueKey('referred-list-more')), findsNothing);
    });

    testWidgets('with nobody to list there is nothing to fold', (tester) async {
      await pumpWith(tester, const ReferralProgress(directReferrals: 0));

      expect(find.byKey(const ValueKey('referred-list-arrow')), findsNothing);
      expect(find.textContaining('Nobody has joined'), findsOneWidget);
    });
  });

  group('the graph and the level bar follow the transactions', () {
    Future<void> pumpWith(WidgetTester tester, ReferralProgress progress) async {
      tester.view.physicalSize = const Size(400, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ReferEarnScreen(progress: progress)));
      await tester.pumpAndSettle();
    }

    /// The graph painter, read off the widget: where the marker sets off from
    /// (0 = the start of the climb, k = the k-th rung) and how far it has gone.
    dynamic graphPainter(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(RewardGraph),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter != null,
          ),
        ),
      );
      return paint.painter;
    }

    testWidgets('the marker leaves the start on the first transaction', (
      tester,
    ) async {
      await pumpWith(tester, const ReferralProgress(directReferrals: 0));
      var painter = graphPainter(tester);
      expect([painter.markerIndex, painter.markerAdvance], [0, 0.0]);

      // One of the two Starter asks for: halfway from the start to Starter,
      // before any level is cleared.
      await pumpWith(tester, const ReferralProgress(directReferrals: 1));
      painter = graphPainter(tester);
      expect(painter.cleared, 0);
      expect(painter.markerIndex, 0);
      expect(painter.markerAdvance, 0.5);
    });

    testWidgets('the marker climbs on across the rungs it clears', (tester) async {
      // Starter cleared, three of the five Riser asks for.
      await pumpWith(tester, const ReferralProgress(directReferrals: 3));
      var painter = graphPainter(tester);
      expect(painter.cleared, 1);
      expect(painter.markerIndex, 1);
      expect(painter.markerAdvance, closeTo(1 / 3, 1e-9));

      // The whole ladder: parked on the last rung.
      await pumpWith(tester, const ReferralProgress(directReferrals: 40));
      painter = graphPainter(tester);
      expect(painter.cleared, 5);
      expect(painter.markerIndex, 5);
      expect(painter.markerAdvance, 0.0);
    });

    testWidgets('a joined-but-unpaid friend does not move the marker', (
      tester,
    ) async {
      await pumpWith(
        tester,
        const ReferralProgress(directReferrals: 0, pendingReferrals: 9),
      );
      final painter = graphPainter(tester);
      expect([painter.markerIndex, painter.markerAdvance], [0, 0.0]);
    });

    testWidgets('the bar on a rung fills with transactions', (tester) async {
      Finder bars() => find.descendant(
        of: find.byType(JourneyMap),
        matching: find.byType(LinearProgressIndicator),
      );

      await pumpWith(tester, const ReferralProgress(directReferrals: 0));
      expect(tester.widget<LinearProgressIndicator>(bars().first).value, 0.0);

      await pumpWith(tester, const ReferralProgress(directReferrals: 1));
      expect(tester.widget<LinearProgressIndicator>(bars().first).value, 0.5);
      expect(find.text('1/2'), findsOneWidget);

      await pumpWith(tester, const ReferralProgress(directReferrals: 2));
      expect(tester.widget<LinearProgressIndicator>(bars().first).value, 1.0);
    });

    testWidgets('the title says a level is being worked on once it has begun', (
      tester,
    ) async {
      await pumpWith(tester, const ReferralProgress(directReferrals: 0));
      expect(find.text('Not started'), findsOneWidget);

      await pumpWith(tester, const ReferralProgress(directReferrals: 1));
      expect(find.text('Not started'), findsNothing);
      expect(find.text('Working on Level 1 - Starter'), findsOneWidget);

      await pumpWith(tester, const ReferralProgress(directReferrals: 2));
      expect(find.text('Level 1 - Starter'), findsWidgets);
    });

    testWidgets('earned money says it goes to the wallet by itself', (
      tester,
    ) async {
      await pumpWith(tester, const ReferralProgress(directReferrals: 1));
      expect(find.byKey(const ValueKey('wallet-credit-note')), findsNothing);

      await pumpWith(
        tester,
        const ReferralProgress(directReferrals: 1, plansActivated: 1, sahakarMoney: 200),
      );
      expect(find.text('₹200'), findsOneWidget);
      expect(find.text('Added to your wallet automatically'), findsOneWidget);
    });
  });

  group('the page opened from the app', () {
    tearDown(ReferralService.instance.debugReset);

    testWidgets(
      'follows the member as their friend moves from joined to transacted',
      (tester) async {
        tester.view.physicalSize = const Size(400, 3200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        ReferralService.instance.debugSet(
          ReferralProgress(
            directReferrals: 0,
            pendingReferrals: 1,
            invitees: [
              ReferredMember(
                name: 'Nihal K.',
                stage: ReferredStage.joined,
                joinedAt: DateTime(2026, 9, 21),
              ),
            ],
          ),
          code: 'SAHAKAR-4821',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => ReferEarnScreen.open(context),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('SAHAKAR-4821'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('referred-list-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Waiting for their first order'),
          findsOneWidget,
        );

        // The friend makes a paid order; the next reading brings it in.
        ReferralService.instance.debugSet(
          ReferralProgress(
            directReferrals: 1,
            invitees: [
              ReferredMember(
                name: 'Nihal K.',
                stage: ReferredStage.transacted,
                joinedAt: DateTime(2026, 9, 21),
                transactedAt: DateTime(2026, 9, 22),
              ),
            ],
          ),
          code: 'SAHAKAR-4821',
        );
        await tester.pumpAndSettle();

        expect(find.text('Made a transaction'), findsOneWidget);
        expect(
          find.textContaining('Waiting for their first order'),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('pending-referrals-note')),
          findsNothing,
        );
      },
    );
  });
}
