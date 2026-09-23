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
    'opening a tier lands on a real registered agent buried in it, not the '
    'row\'s own start, when one exists',
    (tester) async {
      // Six wide siblings, same shape as the "lands at start" test — except
      // this time one of them (the 5th, not the 1st) is a REAL registered
      // agent, matching production: a district's own downline is usually
      // scattered through a wide row rather than sitting first in it. The
      // real production report this guards against: five already-registered
      // agents "not showing" in the tree even though the code and data were
      // both confirmed correct — they were built, just off both edges,
      // because landing on the row's bare start (the previous fix) still
      // only helps when what's being looked for happens to sort first.
      final regionNames = [for (var i = 0; i < 6; i++) 'Region Number $i'];
      AgentGeo.instance.useHierarchy(
        GeoHierarchy.fromNodes([
          for (var i = 0; i < regionNames.length; i++)
            GeoNode(id: 'r$i', parentId: null, level: AgentLevel.region, name: regionNames[i], sort: i),
        ]),
      );
      const realAgent = Agent(
        id: 'req-real',
        name: 'Real Registered Agent',
        phone: '9895357101',
        agentCode: 'SHD-REG-REAL',
        level: AgentLevel.region,
        active: true,
        parentId: 'nat-001',
        area: 'Region Number 4',
        areaId: 'r4',
      );
      AgentService.instance.addAgent(realAgent);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: AgentTeamTreeScreen(root: national)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Expand ${national.name}'));
      await tester.pumpAndSettle();

      // The real agent's own card — not an open "+" position — is what
      // lands on screen, with zero panning, even though it is 5th of 6.
      final realAgentTopLeft = tester.getTopLeft(find.text('Real Registered Agent'));
      expect(realAgentTopLeft.dx, inInclusiveRange(0, 390));
      expect(realAgentTopLeft.dy, inInclusiveRange(0, 844));
    },
  );
}
