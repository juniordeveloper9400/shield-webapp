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
    'registering a real agent into an already-open seat, without leaving '
    'this screen, keeps everything drilled into beneath it open',
    (tester) async {
      // Reported for real as: drill down to a district, then (from this
      // same "My Team" screen, via its own "+ Add agent" flow) register a
      // new agent into the REGION seat above it — South India — and the
      // district that was visible a moment ago vanishes, reading as if the
      // whole branch had silently collapsed.
      //
      // The actual cause: an open seat's id is built from its PARENT's own
      // current id (`slot/<parent>/<tier>/<geoId>`). South India going from
      // an open "+" to a real agent changes what id every seat under it —
      // Kerala, and Kerala's own district — is now built with, even though
      // neither of them personally changed. _expanded went on holding the
      // old ids, which the tree stopped building cards for entirely.
      AgentGeo.instance.useHierarchy(
        GeoHierarchy.fromNodes(const [
          GeoNode(id: 'south', parentId: null, level: AgentLevel.region, name: 'South'),
          GeoNode(id: 'kerala', parentId: 'south', level: AgentLevel.state, name: 'Kerala'),
          GeoNode(id: 'tvm', parentId: 'kerala', level: AgentLevel.district, name: 'Thiruvananthapuram'),
        ]),
      );

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
      expect(find.text('Thiruvananthapuram'), findsOneWidget);

      // A registration completing without navigating away from this screen
      // notifies AgentService exactly like this — no rebuild of the screen
      // itself, just a new row on the roster.
      final nihal = Agent(
        id: 'nihal-1',
        name: 'Nihal',
        phone: '9000000001',
        agentCode: 'SHD-REG-001',
        level: AgentLevel.region,
        active: true,
        parentId: national.id,
        area: 'South',
        areaId: 'south',
      );
      AgentService.instance.addAgent(nihal);
      await tester.pumpAndSettle();

      expect(find.text('Nihal'), findsOneWidget);
      expect(find.text('Kerala'), findsOneWidget);
      expect(find.text('Thiruvananthapuram'), findsOneWidget);
    },
  );
}
