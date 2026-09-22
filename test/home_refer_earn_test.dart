import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shield/data/backend/persona_repository.dart';

import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/auth/auth_service.dart';
import 'package:shield/module/home/refer_earn_card.dart';
import 'package:shield/module/investor/investor_directory.dart';
import 'package:shield/module/investor/investor_access_card.dart';
import 'package:shield/module/agent/agent_portal_card.dart';
import 'package:shield/module/persona/persona_service.dart';
import 'package:shield/screens/home_screen.dart';

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

/// The home slot: Refer & Earn for a plain member, the Agent Portal for an
/// agent, the Investor Access card for an investor — never Refer & Earn beside
/// either of the last two.
void main() {
  Future<void> pumpHome(WidgetTester tester, String phone) async {
    tester.view.physicalSize = const Size(400, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    AuthService.instance.signInAs(phone: phone);
    PersonaService.instance.reload(phone);
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
  }

  setUp(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
    PersonaService.instance.reset();
    PersonaService.instance.debugSetLoader((_) async => PersonaSnapshot.none);
  });
  tearDown(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
    PersonaService.instance.reset();
  });

  testWidgets('a plain member gets the Refer & Earn card', (tester) async {
    await pumpHome(tester, _memberPhone);

    expect(find.byType(ReferEarnCard), findsOneWidget);
    expect(find.byType(AgentPortalCard), findsNothing);
    expect(find.byType(InvestorAccessCard), findsNothing);
  });

  testWidgets('an agent gets the Agent Portal instead', (tester) async {
    AgentService.instance.addAgent(_agent);
    await pumpHome(tester, _agentPhone);

    expect(find.byType(AgentPortalCard), findsOneWidget);
    expect(find.byType(ReferEarnCard), findsNothing);
  });

  testWidgets('an investor gets the Investor Access card instead', (
    tester,
  ) async {
    await pumpHome(tester, InvestorDirectory.demo.phone);

    expect(find.byType(InvestorAccessCard), findsOneWidget);
    expect(find.byType(ReferEarnCard), findsNothing);
  });
}
