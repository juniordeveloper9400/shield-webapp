import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/account/account_screen.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/auth/auth_service.dart';
import 'package:shield/module/investor/investor_directory.dart';
import 'package:shield/module/menu/menu_drawer.dart';
import 'package:shield/module/persona/persona_service.dart';
import 'package:shield/module/refer/refer_earn_screen.dart';
import 'package:shield/module/rewards/rewards_screen.dart';

const _memberPhone = '9000000001';
const _agentPhone = '9000000002';

const _agent = Agent(
  id: 'db-15',
  name: 'Rahul Nair',
  phone: _agentPhone,
  agentCode: 'SHD-AGT-015',
  level: AgentLevel.ward,
  active: true,
  parentId: 'nat-001',
  area: 'Kerala',
);

/// Refer & Earn belongs to a plain member. An agent or an investor is shown
/// their own details instead and must never meet it — on any screen.
void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  /// Signs in [phone] and lets the persona resolve, as it does on sign-in —
  /// without a backend it resolves to a plain member.
  Future<void> signIn(WidgetTester tester, String phone) async {
    AuthService.instance.signInAs(phone: phone);
    PersonaService.instance.reload(phone);
    await tester.pump();
  }

  setUp(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
    PersonaService.instance.reset();
  });
  tearDown(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
    PersonaService.instance.reset();
  });

  final surfaces = <String, Widget Function()>{
    'the Account tab': () => const AccountScreen(),
    'the menu': () => MenuDrawer(onSelectTab: (_, {subTab}) {}),
  };

  for (final entry in surfaces.entries) {
    group(entry.key, () {
      testWidgets('offers Refer & Earn to a plain member', (tester) async {
        await signIn(tester, _memberPhone);
        await pumpScreen(tester, entry.value());

        expect(find.textMatching('Refer & [Ee]arn'), findsOneWidget);
      });

      testWidgets('shows an agent no sign of it', (tester) async {
        await signIn(tester, _agentPhone);
        AgentService.instance.addAgent(_agent);
        await pumpScreen(tester, entry.value());

        expect(find.textMatching('Refer & [Ee]arn'), findsNothing);
      });

      testWidgets('shows an investor no sign of it', (tester) async {
        await signIn(tester, InvestorDirectory.demo.phone);
        await pumpScreen(tester, entry.value());

        expect(find.textMatching('Refer & [Ee]arn'), findsNothing);
      });

      testWidgets('waits for the persona rather than flashing it at an agent', (
        tester,
      ) async {
        AuthService.instance.signInAs(phone: _agentPhone);
        AgentService.instance.addAgent(_agent);
        await pumpScreen(tester, entry.value());
        expect(find.textMatching('Refer & [Ee]arn'), findsNothing);

        // Even a plain member has to wait for the answer before it appears.
        AuthService.instance.signInAs(phone: _memberPhone);
        AgentService.instance.reset();
        PersonaService.instance.reload(_memberPhone);
        await tester.pumpAndSettle();
        expect(find.textMatching('Refer & [Ee]arn'), findsOneWidget);
      });

      testWidgets('takes it away in place when a member is converted', (
        tester,
      ) async {
        await signIn(tester, _agentPhone);
        await pumpScreen(tester, entry.value());
        expect(find.textMatching('Refer & [Ee]arn'), findsOneWidget);

        AgentService.instance.applyRemoteAgent(_agent);
        await tester.pumpAndSettle();

        expect(find.textMatching('Refer & [Ee]arn'), findsNothing);
      });
    });
  }

  group('the Account row', () {
    testWidgets('opens the Refer & Earn screen', (tester) async {
      await signIn(tester, _memberPhone);
      await pumpScreen(tester, const AccountScreen());

      final row = find.text('Refer & Earn');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(ReferEarnScreen), findsOneWidget);
    });
  });

  group('the Rewards screen', () {
    testWidgets('offers the Refer & Earn card to a plain member', (
      tester,
    ) async {
      await signIn(tester, _memberPhone);
      await pumpScreen(tester, const RewardsScreen());

      expect(find.text('GET INSTANT COINS'), findsOneWidget);
      expect(find.textMatching('Refer & [Ee]arn'), findsOneWidget);
    });

    testWidgets('drops the card and its heading for an agent', (tester) async {
      await signIn(tester, _agentPhone);
      AgentService.instance.addAgent(_agent);
      await pumpScreen(tester, const RewardsScreen());

      expect(find.text('GET INSTANT COINS'), findsNothing);
      expect(find.textMatching('Refer & [Ee]arn'), findsNothing);
    });

    testWidgets('drops the card and its heading for an investor', (
      tester,
    ) async {
      await signIn(tester, InvestorDirectory.demo.phone);
      await pumpScreen(tester, const RewardsScreen());

      expect(find.text('GET INSTANT COINS'), findsNothing);
      expect(find.textMatching('Refer & [Ee]arn'), findsNothing);
    });
  });
}

extension on CommonFinders {
  /// Text matching [pattern] anywhere in the string.
  Finder textMatching(String pattern) {
    final regex = RegExp(pattern);
    return byWidgetPredicate(
      (widget) => widget is Text && regex.hasMatch(widget.data ?? ''),
      description: 'Text matching /$pattern/',
    );
  }
}
