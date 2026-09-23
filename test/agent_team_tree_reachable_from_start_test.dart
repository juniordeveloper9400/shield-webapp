import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/agent_geo_repository.dart';
import 'package:shield/module/agent/agent_directory.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/agent/agent_team_tree_screen.dart';

void main() {
  final national = AgentDirectory.national;

  setUp(AgentService.instance.reset);
  tearDown(AgentService.instance.reset);

  testWidgets(
    'opening a tier lands its first sibling on screen, not just whichever '
    'ones sit nearest the row\'s own middle',
    (tester) async {
      // Six siblings — the real region count under national — each wide
      // enough (a long name) that, at 1x zoom on a phone-width viewport,
      // nowhere near all six fit at once. _flowTo used to always centre the
      // TAPPED card (national, here) over its children, which only ever
      // brought the two siblings nearest the exact middle into view —
      // reported for real as: opening National shows East/West India, but
      // South India (the one that actually leads to Kerala) is off both
      // edges with nothing on screen to suggest panning would find it.
      final regionNames = [for (var i = 0; i < 6; i++) 'Region Number $i'];
      AgentGeo.instance.useHierarchy(
        GeoHierarchy.fromNodes([
          for (var i = 0; i < regionNames.length; i++)
            GeoNode(id: 'r$i', parentId: null, level: AgentLevel.region, name: regionNames[i], sort: i),
        ]),
      );

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: AgentTeamTreeScreen(root: national)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Expand ${national.name}'));
      await tester.pumpAndSettle();

      // Every sibling actually built...
      for (final name in regionNames) {
        expect(find.text(name), findsOneWidget);
      }
      // ...and the FIRST one lands on screen without any panning — the row
      // starts right where the tapped card (national) now sits, rather than
      // being centred symmetrically under it.
      final firstTopLeft = tester.getTopLeft(find.text(regionNames.first));
      expect(firstTopLeft.dx, inInclusiveRange(0, 390));
      expect(firstTopLeft.dy, inInclusiveRange(0, 844));
    },
  );
}
