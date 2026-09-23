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
    'assembly count) fits it on screen instead of gliding most of it off '
    'both edges',
    (tester) async {
      // A district with as many named children as Malappuram's real 17
      // assemblies — wider than any tier above it (South's own 8 states,
      // Kerala's 14 districts). _flowTo used to zoom in to at least 1x
      // unconditionally, so this tier's own siblings spilled past both
      // sides of the viewport — nothing wrong with the data or the widgets
      // built, just nothing left inside the frame to look at, which reads
      // exactly like the chevron did nothing (or, worse, like the view
      // slid back up to whatever tier was last fully on screen).
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

      // A real phone width, not a tablet-sized test canvas — the narrower
      // the viewport, the more of a 17-wide row spills past its edges at a
      // scale that fit a 6- or 14-wide tier.
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

      // Every one of the 17 siblings actually built...
      for (final name in assemblyNames) {
        expect(find.text(name), findsOneWidget);
      }
      // ...and, the actual bug this guards against, actually visible: the
      // first and last of the 17 both land inside the viewport, not off one
      // edge or both. (A weaker "scale >= 1.0" check here would pass even
      // while every sibling but Malappuram's own card sat off-screen — 1x is
      // exactly the scale that was too zoomed-in to fit a 17-wide row.)
      bool onScreen(Finder finder) {
        final topLeft = tester.getTopLeft(finder);
        return topLeft.dx >= 0 &&
            topLeft.dx <= 390 &&
            topLeft.dy >= 0 &&
            topLeft.dy <= 844;
      }

      expect(onScreen(find.text('Malappuram')), isTrue);
      expect(onScreen(find.text(assemblyNames.first)), isTrue);
      expect(onScreen(find.text(assemblyNames.last)), isTrue);
    },
  );
}
