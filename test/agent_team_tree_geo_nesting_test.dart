import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/agent_geo_repository.dart';
import 'package:shield/module/agent/agent_directory.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/agent/agent_team_tree_screen.dart';

/// South → Kerala → {Ernakulam, Malappuram} — enough tiers to register an
/// agent well below the nearest open seat, the same shape a real "convert
/// with no parent chosen" registration produces.
void _seedGeo() {
  AgentGeo.instance.useHierarchy(
    GeoHierarchy.fromNodes(const [
      GeoNode(
        id: 'south',
        parentId: null,
        level: AgentLevel.region,
        name: 'South',
      ),
      GeoNode(
        id: 'karnataka',
        parentId: 'south',
        level: AgentLevel.state,
        name: 'Karnataka',
      ),
      GeoNode(
        id: 'kerala',
        parentId: 'south',
        level: AgentLevel.state,
        name: 'Kerala',
      ),
      GeoNode(
        id: 'ernakulam',
        parentId: 'kerala',
        level: AgentLevel.district,
        name: 'Ernakulam',
      ),
      GeoNode(
        id: 'malappuram',
        parentId: 'kerala',
        level: AgentLevel.district,
        name: 'Malappuram',
      ),
    ]),
  );
}

void main() {
  final national = AgentDirectory.national;

  setUp(AgentService.instance.reset);
  tearDown(AgentService.instance.reset);

  Future<void> pumpTree(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AgentTeamTreeScreen(root: national)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    "opening a skip-level agent's own chevron does not collapse the open "
    'geo seat it is nested under',
    (tester) async {
      _seedGeo();
      // Registered at state level under Kerala, but with no region agent in
      // between — parentId points straight at national, the same skip-level
      // shape deriveParentAgentId produces for real. See AgentService.
      // agentAtSlot's doc.
      const kerala = Agent(
        id: 'req-9',
        name: 'Althaf',
        phone: '9895357101',
        agentCode: 'SHD-STE-R9',
        level: AgentLevel.state,
        active: false,
        parentId: 'nat-001',
        area: 'Kerala',
        areaId: 'kerala',
        approvalStatus: AgentApprovalStatus.pending,
      );
      AgentService.instance.addAgent(kerala);
      await pumpTree(tester);

      await tester.tap(find.byTooltip('Expand ${national.name}'));
      await tester.pumpAndSettle();
      // The only real seat under National is the open South region — Kerala
      // sits several tiers below it, out of sight until South is opened.
      await tester.tap(find.byTooltip('Expand Region position'));
      await tester.pumpAndSettle();

      expect(find.text('Karnataka'), findsOneWidget);
      expect(find.text('Althaf'), findsOneWidget);

      // Opening Althaf's own chevron must not collapse South back out from
      // under it — the actual bug: it used to, because the accordion's
      // "keep only ancestors" rule read parentId alone (straight to
      // national) and had no idea an open geo seat also enclosed this card.
      await tester.tap(find.byTooltip('Expand Althaf'));
      await tester.pumpAndSettle();

      expect(find.text('Karnataka'), findsOneWidget);
      expect(find.text('Althaf'), findsOneWidget);
      expect(find.text('Ernakulam'), findsOneWidget);
      expect(find.text('Malappuram'), findsOneWidget);
    },
  );
}
