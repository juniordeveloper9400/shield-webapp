import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/account/account_screen.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/auth/auth_service.dart';

const _phone = '9000000002';

const _agent = Agent(
  id: 'db-15',
  name: 'Rahul Nair',
  phone: _phone,
  agentCode: 'SHD-AGT-015',
  level: AgentLevel.ward,
  active: true,
  parentId: 'nat-001',
  area: 'Kerala',
);

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: AccountScreen()));
    await tester.pumpAndSettle();
  }

  setUp(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
    AuthService.instance.signInAs(phone: _phone);
  });
  tearDown(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
  });

  group('the profile card ID line', () {
    testWidgets('shows the Member ID for a plain member', (tester) async {
      await pump(tester);

      expect(find.textContaining('Member ID:'), findsOneWidget);
      expect(find.textContaining('Agent ID:'), findsNothing);
      expect(find.text('Become a SHIELD Agent'), findsOneWidget);
    });

    testWidgets('shows the Agent ID instead of the Member ID for an agent', (
      tester,
    ) async {
      AgentService.instance.addAgent(_agent);

      await pump(tester);

      expect(find.text('Agent ID: SHD-AGT-015'), findsOneWidget);
      expect(find.textContaining('Member ID'), findsNothing);
    });

    testWidgets('swaps in place when the admin converts the member while the '
        'account tab is open', (tester) async {
      await pump(tester);
      expect(find.textContaining('Member ID:'), findsOneWidget);

      AgentService.instance.applyRemoteAgent(_agent);
      await tester.pumpAndSettle();

      expect(find.text('Agent ID: SHD-AGT-015'), findsOneWidget);
      expect(find.textContaining('Member ID'), findsNothing);
      // The Agent Portal row flips in the same rebuild, so the two agree.
      expect(find.text('Agent Portal'), findsOneWidget);
      expect(find.text('Become a SHIELD Agent'), findsNothing);
    });

    testWidgets('a recruit still pending approval keeps the Member ID', (
      tester,
    ) async {
      AgentService.instance.addAgent(
        Agent(
          id: _agent.id,
          name: _agent.name,
          phone: _agent.phone,
          agentCode: _agent.agentCode,
          level: _agent.level,
          active: true,
          parentId: _agent.parentId,
          area: _agent.area,
          approvalStatus: AgentApprovalStatus.pending,
        ),
      );

      await pump(tester);

      expect(find.textContaining('Member ID:'), findsOneWidget);
      expect(find.textContaining('Agent ID:'), findsNothing);
    });

    testWidgets('tapping the Agent ID copies it and says so', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      AgentService.instance.addAgent(_agent);
      await pump(tester);

      await tester.tap(find.text('Agent ID: SHD-AGT-015'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(copied, 'SHD-AGT-015');
      expect(find.text('Agent ID copied'), findsOneWidget);
    });
  });
}
