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
    'assembly count) zooms in and lands on the start of the row, rather '
    'than shrinking it to fit or centring on whichever siblings happen to '
    'sit in the middle',
    (tester) async {
      // A district with as many named children as Malappuram's real 17
      // assemblies — wider than any tier above it (South's own states,
      // Kerala's 14 districts). Two things were tried and reverted before
      // this: zooming OUT to force all 17 into frame at once shrank the
      // newly-opened cards to the point of being unreadable; centring the
      // tapped card (Malappuram) over its own children only ever brought
      // whichever couple of siblings sat nearest the row's exact middle
      // into view, which for the real district data left the sibling
      // actually being looked for off both edges. Landing on the row's own
      // start — so the first sibling is what's on screen, panning right for
      // the rest — is the wanted behaviour instead; the tapped card itself
      // scrolling out of view above is an acceptable trade, since it was
      // already seen and tapped to get here.
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
      // ...the FIRST of them lands on screen without any panning, zoomed in
      // (not shrunk down trying to fit all 17 into view)...
      final firstTopLeft = tester.getTopLeft(find.text(assemblyNames.first));
      expect(firstTopLeft.dx, inInclusiveRange(0, 390));
      expect(firstTopLeft.dy, inInclusiveRange(0, 844));
      final interactiveViewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(interactiveViewer.transformationController!.value.getMaxScaleOnAxis(), greaterThanOrEqualTo(1.0));
    },
  );
}
