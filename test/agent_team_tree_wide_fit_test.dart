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
    'expanding a wide tier (17 siblings, matching Malappuram\'s real '
    'assembly count) still zooms in on the tapped card, rather than '
    'shrinking the whole row to fit',
    (tester) async {
      // A district with as many named children as Malappuram's real 17
      // assemblies — wider than any tier above it (South's own states,
      // Kerala's 14 districts). Zooming OUT to force all 17 into frame at
      // once was tried and reverted: it shrank the newly-opened cards to
      // the point of being unreadable. The tapped card zooming IN, with the
      // rest of a wide row reachable by panning sideways (an ordinary
      // zoomed-in map), is the wanted behaviour instead.
      final assemblyNames = [
        for (var i = 0; i < 17; i++) 'Assembly $i',
      ];
      AgentGeo.instance.useHierarchy(
        GeoHierarchy.fromNodes([
          const GeoNode(id: 'south', parentId: null, level: AgentLevel.region, name: 'South'),
          const GeoNode(id: 'kerala', parentId: 'south', level: AgentLevel.state, name: 'Kerala'),
          const GeoNode(id: 'malappuram', parentId: 'kerala', level: AgentLevel.district, name: 'Malappuram'),
          for (var i = 0; i < assemblyNames.length; i++)
            GeoNode(id: 'a$i', parentId: 'malappuram', level: AgentLevel.assembly, name: assemblyNames[i]),
        ]),
      );

      // A real phone width, not a tablet-sized test canvas.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: AgentTeamTreeScreen(root: national)));
      await tester.pumpAndSettle();

      Future<void> tap(String tooltip) async {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
      }

      await tap('Expand ${national.name}');
      await tap('Expand Region position');
      await tap('Expand State position');
      await tap('Expand District position');

      // Every one of the 17 siblings actually built, even though only some
      // fit in the frame at once...
      for (final name in assemblyNames) {
        expect(find.text(name), findsOneWidget);
      }
      // ...the tapped card (Malappuram) itself is on screen and zoomed in,
      // not shrunk down trying to fit its whole wide row into view...
      final malappuramTopLeft = tester.getTopLeft(find.text('Malappuram'));
      expect(malappuramTopLeft.dx, inInclusiveRange(0, 390));
      expect(malappuramTopLeft.dy, inInclusiveRange(0, 844));
      final interactiveViewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(interactiveViewer.transformationController!.value.getMaxScaleOnAxis(), greaterThanOrEqualTo(1.0));
    },
  );
}
