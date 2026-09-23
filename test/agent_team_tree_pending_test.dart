import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/agent_geo_repository.dart';
import 'package:shield/module/agent/agent_directory.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/agent/agent_team_tree_screen.dart';

void main() {
  final national = AgentDirectory.national;

  // "My Team" refuses to draw the tree at all — showing a "no database
  // connection" / retry status screen instead — until AgentGeo.current has
  // at least one region (see agent_team_tree_screen.dart's own doc on why:
  // drawing off a half-populated hierarchy would show a generic "+ District"
  // where a real district name is just a round-trip away). A single region
  // node is enough to clear that gate; this test's own agent uses the plain
  // doubling capacity ([AgentLevel.childCapacity]), not a named geo slot, so
  // nothing more detailed is needed.
  setUp(() {
    AgentService.instance.reset();
    AgentGeo.instance.useHierarchy(
      GeoHierarchy.fromNodes(const [
        // Named deliberately unlike anything this test's own agent uses
        // (its `area` is the free-text 'South') — this fixture exists only
        // to clear the screen's "no hierarchy loaded" gate, not to back a
        // named slot for that agent.
        GeoNode(
          id: 'unrelated-region',
          parentId: null,
          level: AgentLevel.region,
          name: 'Unrelated Region',
        ),
      ]),
    );
  });
  tearDown(() {
    AgentService.instance.reset();
    AgentGeo.instance.reset();
  });

  Future<void> pumpTree(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: AgentTeamTreeScreen(root: national)),
    );
    await tester.pumpAndSettle();
  }

  group('a card still awaiting approval', () {
    const pendingRegion = Agent(
      id: 'db-901',
      name: 'Vinu Das',
      phone: '9812300000',
      agentCode: 'SHD-REG-009',
      level: AgentLevel.region,
      active: true,
      parentId: 'nat-001',
      area: 'South',
      approvalStatus: AgentApprovalStatus.pending,
    );

    testWidgets('shows the lock and the Pending approval badge, as before', (
      tester,
    ) async {
      AgentService.instance.addAgent(pendingRegion);
      await pumpTree(tester);

      await tester.tap(find.byTooltip('Expand ${national.name}'));
      await tester.pumpAndSettle();

      expect(find.text('Pending approval'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets(
      'still expands to preview the tier it would head — visibility is not '
      'what approval gates',
      (tester) async {
        AgentService.instance.addAgent(pendingRegion);
        await pumpTree(tester);

        await tester.tap(find.byTooltip('Expand ${national.name}'));
        await tester.pumpAndSettle();

        // The chevron exists even though the card is locked …
        expect(find.byTooltip('Expand Vinu Das'), findsOneWidget);

        // … and tapping it fans out the state tier below, the same open-slot
        // preview an approved agent's card would show.
        await tester.tap(find.byTooltip('Expand Vinu Das'));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Add a state agent here'), findsWidgets);
      },
    );

    testWidgets('the card body still declines to open — nothing to review '
        'there yet', (tester) async {
      AgentService.instance.addAgent(pendingRegion);
      await pumpTree(tester);

      await tester.tap(find.byTooltip('Expand ${national.name}'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vinu Das'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Not yet approved'),
        findsOneWidget,
      );
    });
  });
}
