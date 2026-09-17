import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';

/// A minimal fully-formed agent for a synthetic parent chain — every field
/// [Agent] doesn't care about for commission math left at its default.
Agent _agent({
  required String id,
  required AgentLevel level,
  String? parentId,
  int personalSales = 0,
}) {
  return Agent(
    id: id,
    name: 'Test $id',
    phone: '90000000$id'.substring(0, 10),
    agentCode: 'SHD-TEST-$id',
    level: level,
    active: true,
    parentId: parentId,
    area: '',
    personalSales: personalSales,
  );
}

void main() {
  // Mirrors the exact worked examples verified live against the real
  // backend function (app.approve_wallet_card_activation, migrations
  // 0033-0040) earlier this session — a district agent selling ₹10,000
  // credits 600/100/60/50 to itself/state/region/national. This test
  // exists so the client-side "Team sales" display, which used to apply
  // one flat 2% regardless of distance, is now provably reading the same
  // decaying-by-hop numbers the agent is actually paid.
  test(
    'commissionFrom walks the real parent chain with the backend\'s exact decaying rate',
    () {
      final service = AgentService.instance;
      addTearDown(service.reset);

      final national = _agent(id: 'nat', level: AgentLevel.national);
      final region = _agent(id: 'reg', level: AgentLevel.region, parentId: 'nat');
      final state = _agent(id: 'sta', level: AgentLevel.state, parentId: 'reg');
      final district = _agent(
        id: 'dis',
        level: AgentLevel.district,
        parentId: 'sta',
        personalSales: 10000,
      );

      service.addAgent(national);
      service.addAgent(region);
      service.addAgent(state);
      service.addAgent(district);

      // hop 1 (state <- district): 10% of the 10% pool = 1% of 10,000.
      expect(service.commissionFrom(state, district), 100);
      // hop 2 (region <- district): 6% of the pool.
      expect(service.commissionFrom(region, district), 60);
      // hop 3 (national <- district): 5% of the pool.
      expect(service.commissionFrom(national, district), 50);

      // The whole downline's total override for each viewer — just this
      // one district seller here, so it matches the single-hop figures.
      expect(service.teamCommission(state), 100);
      expect(service.teamCommission(region), 60);
      expect(service.teamCommission(national), 50);

      // An agent is never their own override source.
      expect(service.commissionFrom(district, district), 0);
    },
  );

  test('commissionFrom is zero when the chain never actually reaches the viewer', () {
    final service = AgentService.instance;
    addTearDown(service.reset);

    // Two unrelated trees — "cousin" has no path up to "outsider" at all.
    final outsider = _agent(id: 'out', level: AgentLevel.national);
    final orphan = _agent(
      id: 'orp',
      level: AgentLevel.state,
      parentId: null,
      personalSales: 10000,
    );
    service.addAgent(outsider);
    service.addAgent(orphan);

    expect(service.commissionFrom(outsider, orphan), 0);
  });

  test('commissionFrom is zero past the 6-hop table, matching the backend\'s own cutoff', () {
    final service = AgentService.instance;
    addTearDown(service.reset);

    // Eight levels deep: national at the top, ward at the bottom is 6 hops
    // from national's own hop-1 child — a 7th hop would be needed to reach
    // national from an 8th level, past what the backend's own v_hop_rates
    // (migrations 0036-0039) covers.
    final ids = ['l0', 'l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l7'];
    String? parent;
    for (final id in ids) {
      service.addAgent(_agent(id: id, level: AgentLevel.national, parentId: parent, personalSales: 10000));
      parent = id;
    }
    final top = service.byId('l0')!;
    final seventhHop = service.byId('l7')!;

    // l7's chain up to l0 is 7 hops — one past hopOverridePercents' length.
    expect(service.commissionFrom(top, seventhHop), 0);
    // l6 is only 6 hops from l0 — still covered, at the table's last rate.
    final sixthHop = service.byId('l6')!;
    expect(service.commissionFrom(top, sixthHop), 20);
  });
}
