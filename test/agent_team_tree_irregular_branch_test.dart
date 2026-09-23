import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/agent_geo_repository.dart';
import 'package:shield/module/agent/agent_directory.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/agent/agent_team_tree_screen.dart';

/// South → Kerala → Malappuram → Perinthalmanna, where Perinthalmanna's own
/// children are NOT all the same tier — one real LSGD plus one ward whose
/// `lsgd_id` skips straight to the assembly (the exact "irregular branch"
/// `GeoHierarchy.childLevelOfId`'s own doc warns about, and what migration
/// 0058's LSGD-code cleanup exists to catch in the real Kerala import).
/// `childLevelOfId(perinthalmanna)` reports only the FIRST child's tier
/// ('lsgd', since it sorts first) — every open position under Perinthalmanna
/// must still be labelled by its OWN slot's tier, not that one shared guess.
void _seedGeo() {
  AgentGeo.instance.useHierarchy(
    GeoHierarchy.fromNodes(const [
      GeoNode(id: 'south', parentId: null, level: AgentLevel.region, name: 'South'),
      GeoNode(id: 'kerala', parentId: 'south', level: AgentLevel.state, name: 'Kerala'),
      GeoNode(id: 'malappuram', parentId: 'kerala', level: AgentLevel.district, name: 'Malappuram'),
      GeoNode(id: 'perinthalmanna', parentId: 'malappuram', level: AgentLevel.assembly, name: 'Perinthalmanna'),
      GeoNode(id: 'normalpanchayat', parentId: 'perinthalmanna', level: AgentLevel.lsgd, name: 'Normal Panchayat', sort: 0),
      GeoNode(id: 'skipward', parentId: 'perinthalmanna', level: AgentLevel.ward, name: 'Skip Ward', sort: 1),
    ]),
  );
}

void main() {
  final national = AgentDirectory.national;

  setUp(AgentService.instance.reset);
  tearDown(AgentService.instance.reset);

  testWidgets(
    "an assembly's open positions are each labelled by their own real tier, "
    'not the tier its first child happens to be',
    (tester) async {
      _seedGeo();
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AgentTeamTreeScreen(root: national)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Expand ${national.name}'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand Region position'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand State position'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand District position'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand Assembly position'));
      await tester.pumpAndSettle();

      // Before the fix both positions were forced onto whichever tier
      // childLevelOfId guessed from the first child alone — Normal Panchayat
      // read correctly by coincidence, but Skip Ward was mislabelled "Add a
      // lsgd agent here" instead of its own real "ward" tier.
      expect(find.byTooltip('Add a lsgd agent here'), findsOneWidget);
      expect(find.byTooltip('Add a ward agent here'), findsOneWidget);
    },
  );
}
