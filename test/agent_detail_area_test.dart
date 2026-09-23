import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/agent/agent_detail_screen.dart';
import 'package:shield/module/agent/agent_directory.dart';
import 'package:shield/module/agent/agent_model.dart';

void main() {
  testWidgets(
    "the national agent's own detail hides Area — it heads every region, "
    "not the one its seed data happens to carry",
    (tester) async {
      // AgentDirectory.national carries area: 'Kerala', a leftover from
      // before the six-region hierarchy existed. Showing it verbatim on
      // National's own detail screen reads as if National were scoped to
      // Kerala alone, rather than heading all six regions.
      await tester.pumpWidget(
        MaterialApp(home: AgentDetailScreen(agent: AgentDirectory.national)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Area'), findsNothing);
    },
  );

  testWidgets(
    'a real registered agent still shows its own actual area',
    (tester) async {
      const district = Agent(
        id: 'dist-1',
        name: 'Test District Agent',
        phone: '9000000000',
        agentCode: 'SHD-DIS-001',
        level: AgentLevel.district,
        active: true,
        parentId: 'nat-001',
        area: 'Thiruvananthapuram',
        areaId: 'tvm-id',
      );
      await tester.pumpWidget(MaterialApp(home: AgentDetailScreen(agent: district)));
      await tester.pumpAndSettle();

      expect(find.text('Area'), findsOneWidget);
      expect(find.text('Thiruvananthapuram'), findsOneWidget);
    },
  );
}
