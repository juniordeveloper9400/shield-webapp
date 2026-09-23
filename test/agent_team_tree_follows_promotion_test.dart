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
    'the camera follows a seat that was already open when a registration '
    'promotes it to a real agent, rather than leaving the view where it '
    'was and looking untouched',
    (tester) async {
      // Reported for real as: "click the hierarchy, it collapses, going
      // upward". The previous fix (agent_team_tree_survives_promotion_test)
      // correctly kept a promoted seat's own _expanded entry alive across
      // the id change, but never moved the camera to show it — so its card
      // sat off-screen still showing an up-arrow (already expanded) that
      // looked, to someone who hadn't scrolled to see it, like an untouched
      // down-arrow waiting to be opened. Tapping it then did exactly what
      // an already-open arrow is supposed to do: closed it, and glided the
      // view up to its parent — which reads exactly like "the hierarchy
      // collapsed" for a seat nobody had actually touched since it opened.
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

      // Not just built — actually on screen, without any further tap or
      // pan, so the newly-promoted card's already-expanded arrow is what
      // greets whoever registered them, not an untouched-looking view of
      // wherever the camera happened to be beforehand.
      final nihalTopLeft = tester.getTopLeft(find.text('Nihal'));
      expect(nihalTopLeft.dx, inInclusiveRange(0, 390));
      expect(nihalTopLeft.dy, inInclusiveRange(0, 844));
    },
  );
}
