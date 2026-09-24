import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/agent_geo_repository.dart';
import 'package:shield/module/agent/agent_directory.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/agent/agent_team_tree_screen.dart';

void main() {
  setUp(AgentService.instance.reset);
  tearDown(AgentService.instance.reset);

  testWidgets(
    'collapsing an agent whose recorded parent is the OTHER national row '
    'still glides the camera somewhere real, when a second real national '
    'agent — not the local seed — is this tree\'s own root',
    (tester) async {
      // The database can (and, per decision-log.md, currently does) hold
      // more than one NATIONAL-level app.agent row. AgentRepository._toAgent
      // maps a NULL app.agent.parent_id to AgentDirectory.national.id — the
      // bundled seed persona's own id — which is exactly correct when that
      // seed really is the signed-in root, but a dangling reference to an
      // agent that plays no part in the tree at all when the person signed
      // in is a *different* real national agent instead. Reported for real
      // as: collapse a district agent's own chevron and the view goes
      // nowhere, or ends up somewhere that reads as a totally different,
      // empty part of the hierarchy.
      AgentGeo.instance.useHierarchy(
        GeoHierarchy.fromNodes(const [
          GeoNode(id: 'south', parentId: null, level: AgentLevel.region, name: 'South'),
          GeoNode(id: 'kerala', parentId: 'south', level: AgentLevel.state, name: 'Kerala'),
          GeoNode(id: 'idukki', parentId: 'kerala', level: AgentLevel.district, name: 'Idukki'),
          GeoNode(id: 'asm1', parentId: 'idukki', level: AgentLevel.assembly, name: 'SomeAssembly'),
        ]),
      );

      // Muzaa: a second, real NATIONAL-level agent, distinct from the local
      // seed (AgentDirectory.national) — this tree's actual root.
      const muzaa = Agent(
        id: 'db-86',
        name: 'Muzaa',
        phone: '9400525063',
        agentCode: 'SHD-AGT-005',
        level: AgentLevel.national,
        active: true,
        parentId: null,
        area: '',
      );
      // Shabin: a real district agent whose app.agent.parent_id is NULL —
      // mapped by AgentRepository to AgentDirectory.national.id, exactly
      // like the live data currently does.
      final shabin = Agent(
        id: 'db-83',
        name: 'Muhammad Shabin Nd',
        phone: '9447570284',
        agentCode: 'SHD-AGT-003',
        level: AgentLevel.district,
        active: true,
        parentId: AgentDirectory.national.id,
        area: 'Idukki',
        areaId: 'idukki',
      );
      AgentService.instance.addAgent(muzaa);
      AgentService.instance.addAgent(shabin);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: AgentTeamTreeScreen(root: muzaa)));
      await tester.pumpAndSettle();

      Future<void> tap(String tooltip) async {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
      }

      await tap('Expand ${muzaa.name}');
      await tap('Expand Region position');
      await tap('Expand State position');
      expect(find.text('Muhammad Shabin Nd'), findsOneWidget);

      // Open Shabin's own chevron to reveal his assembly, then collapse it
      // again — the exact "go back" step that was landing nowhere (and, in
      // an earlier version of this fix, overshot all the way up to Muzaa —
      // several tiers further than a single collapse should ever glide).
      await tap('Expand Muhammad Shabin Nd');
      expect(find.text('SomeAssembly'), findsOneWidget);
      await tap('Collapse Muhammad Shabin Nd');

      // Lands one tier up — Kerala, where Shabin actually sits
      // geographically — not all the way at the tree's own root.
      final keralaTopLeft = tester.getTopLeft(find.text('Kerala'));
      expect(keralaTopLeft.dx, inInclusiveRange(0, 390));
      expect(keralaTopLeft.dy, inInclusiveRange(0, 844));
    },
  );
}
