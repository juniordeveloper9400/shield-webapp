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

  testWidgets(
    "opening a district agent's own chevron does not freeze when a real "
    'assembly seat below them shares their own district name',
    (tester) async {
      // Real Kerala geo data reuses the same place name across tiers — an
      // assembly constituency inside a district can be named after the
      // district itself (Idukki district / Idukki assembly, the reported
      // case).
      AgentGeo.instance.useHierarchy(
        GeoHierarchy.fromNodes(const [
          GeoNode(id: 'south', parentId: null, level: AgentLevel.region, name: 'South'),
          GeoNode(id: 'kerala', parentId: 'south', level: AgentLevel.state, name: 'Kerala'),
          GeoNode(id: 'idukki', parentId: 'kerala', level: AgentLevel.district, name: 'Idukki'),
          GeoNode(id: 'idukki-ac', parentId: 'idukki', level: AgentLevel.assembly, name: 'Idukki'),
          GeoNode(id: 'devikulam-ac', parentId: 'idukki', level: AgentLevel.assembly, name: 'Devikulam'),
        ]),
      );
      const shabin = Agent(
        id: 'req-10',
        name: 'Muhammad Shabin Nd',
        phone: '9895357102',
        agentCode: 'SHD-AGT-003',
        level: AgentLevel.district,
        active: true,
        parentId: 'nat-001',
        area: 'Idukki',
        areaId: 'idukki',
        approvalStatus: AgentApprovalStatus.approved,
      );
      AgentService.instance.addAgent(shabin);
      await pumpTree(tester);

      await tester.tap(find.byTooltip('Expand ${national.name}'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand Region position'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand State position'));
      await tester.pumpAndSettle();

      expect(find.text('Muhammad Shabin Nd'), findsOneWidget);

      // This must fan out the two real assembly seats under Idukki, not
      // hang — the actual bug: agentAtSlot matched the "Idukki" assembly
      // seat's name straight back to Shabin's own district-level area name,
      // placing him as his own child and recursing without end.
      await tester.tap(find.byTooltip('Expand Muhammad Shabin Nd'));
      await tester.pumpAndSettle();

      expect(find.text('Devikulam'), findsOneWidget);
    },
  );
}
