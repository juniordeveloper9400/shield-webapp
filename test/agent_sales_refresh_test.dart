import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/agent/agent_directory.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/agent/agent_customer.dart';
import 'package:shield/module/privilege/privilege_tier.dart';

Agent agent(
  String id, {
  String? parent,
  int sales = 0,
  int plans = 0,
  AgentLevel level = AgentLevel.district,
  AgentApprovalStatus approvalStatus = AgentApprovalStatus.approved,
}) => Agent(
  id: id,
  name: id,
  phone: id,
  agentCode: id,
  level: level,
  active: true,
  parentId: parent,
  area: '',
  personalSales: sales,
  plansSold: plans,
  approvalStatus: approvalStatus,
);

void main() {
  final service = AgentService.instance;
  setUp(service.reset);
  tearDown(service.reset);
  test(
    'converted profile already in roster still loads direct customers',
    () async {
      final self = agent('db-1');
      service.applyRemoteAgent(self);
      service.debugSetLoaders(
        team: () async => [self],
        pending: () async => [],
        customers: (id) async => [
          AgentCustomer(
            id: 'customer',
            name: 'Customer',
            phone: '',
            agentId: id,
            plans: [
              CustomerPlan(
                id: 'plan',
                tier: PrivilegeProgramme.silver,
                amount: 10000,
                activatedOn: DateTime(2026, 9, 1),
              ),
            ],
          ),
        ],
      );
      await service.ensureLoaded();
      expect(service.directSaleVolume(self), 10000);
      expect(service.directSaleEarnings(self), 600);
      expect(service.loadError, isNull);
    },
  );
  test(
    'refresh updates existing team sales and removes vanished rows',
    () async {
      final self = agent('db-1');
      var rows = [self, agent('db-2', parent: self.id, sales: 10000)];
      service.debugSetLoaders(
        team: () async => rows,
        pending: () async => [],
        customers: (_) async => [],
      );
      await service.refresh();
      expect(service.teamSalesTotal(self), 10000);
      rows = [self, agent('db-2', parent: self.id, sales: 25000)];
      await service.refresh();
      expect(service.teamSalesTotal(self), 25000);
      rows = [self];
      await service.refresh();
      expect(service.teamSalesTotal(self), 0);
    },
  );
  test(
    'a downline row with no parent chosen still earns the real national '
    'agent an override, not just a team-total count',
    () async {
      // Admin converted Muzaa straight to an assembly-level agent with no
      // parent picked — `AgentRepository` maps that null `parentId` onto the
      // seed national placeholder's id (`AgentDirectory.national.id`), since
      // it has no view of the rest of the roster while mapping one row.
      // Once the real, signed-in national agent (Althaf) has also been
      // fetched, `_loadFromServer` must reparent Muzaa onto Althaf's real
      // id — otherwise `descendantsOf` (which special-cases national) still
      // counts Muzaa's sale in Althaf's team total, but `commissionFrom`
      // (which walks the real `parentId` chain) never finds Althaf above
      // Muzaa and pays nothing.
      final althaf = agent('db-1', level: AgentLevel.national);
      // `AgentRepository._toAgent` maps a real, null server-side `parentId`
      // onto this seed placeholder id — reproduced here directly since
      // `debugSetLoaders` bypasses that mapping.
      final muzaa = agent(
        'db-2',
        parent: AgentDirectory.national.id,
        sales: 10000,
        level: AgentLevel.assembly,
      );
      service.debugSetLoaders(
        team: () async => [althaf, muzaa],
        pending: () async => [],
        customers: (_) async => [],
      );
      await service.refresh();
      expect(service.teamSalesTotal(althaf), 10000);
      expect(service.commissionFrom(althaf, muzaa), greaterThan(0));
      final reparented = service.byId(muzaa.id);
      expect(reparented?.parentId, althaf.id);
      expect(reparented?.parentId, isNot(AgentDirectory.national.id));
    },
  );
  test(
    'agentAtSlot finds whoever holds a geo position by areaId, even when '
    'their real parentId skips straight past it',
    () async {
      // Muzaa registered as an assembly agent under an empty South Region /
      // Kerala / Malappuram chain — `deriveParentAgentId` intentionally
      // skips those vacant tiers for the commission chain, so `parentId`
      // points straight at the national agent. "My Team"'s org-chart tree
      // must still draw Muzaa at the assembly position, nested under those
      // three empty "+" seats, not flattened up next to National's own
      // region row — `agentAtSlot`, not `childrenOf`, is what the tree now
      // walks by to find them there.
      final althaf = agent('db-1', level: AgentLevel.national);
      final muzaa = Agent(
        id: 'db-2',
        name: 'Muzaa',
        phone: 'db-2',
        agentCode: 'SHD-AGT-002',
        level: AgentLevel.assembly,
        active: true,
        parentId: althaf.id,
        area: 'Perinthalmanna',
        areaId: 'assembly/perinthalmanna',
      );
      service.debugSetLoaders(
        team: () async => [althaf, muzaa],
        pending: () async => [],
        customers: (_) async => [],
      );
      await service.refresh();
      expect(service.agentAtSlot('assembly/perinthalmanna'), muzaa);
      // Nobody actually holds the region or district seats above Muzaa —
      // those stay open "+" positions in the tree.
      expect(service.agentAtSlot('south-region'), isNull);
      expect(service.agentAtSlot('kerala'), isNull);
      expect(service.agentAtSlot('malappuram'), isNull);
    },
  );
  test(
    'a team member\'s own plan count survives a refresh, gated on approval '
    'the same way personalSales already is',
    () async {
      // The roster's "Plans" column used to read
      // service.customersOf(member).length — the caller's own Direct Sale
      // customer list, which AgentCustomerRepository only ever fetches for
      // the signed-in agent, not for a team member being viewed from above.
      // It always read 0 for anyone but self. plansSold rides in on the
      // same /v1/agent/team row personalSales already does — every agent in
      // the tree gets their own real count.
      final self = agent('db-1', level: AgentLevel.national);
      final downline = agent(
        'db-2',
        parent: self.id,
        sales: 110000,
        plans: 1,
      );
      service.debugSetLoaders(
        team: () async => [self, downline],
        pending: () async => [],
        customers: (_) async => [],
      );
      await service.refresh();
      expect(service.byId(downline.id)?.displayPlansSold, 1);

      // Same gate personalSales/earned already read through: nothing to
      // show for a recruit nobody has approved yet.
      final pendingAgent = agent(
        'db-3',
        parent: self.id,
        plans: 3,
        approvalStatus: AgentApprovalStatus.pending,
      );
      expect(pendingAgent.displayPlansSold, 0);
    },
  );
  test('failed load remains retryable', () async {
    var attempts = 0;
    final self = agent('db-1');
    service.debugSetLoaders(
      team: () async => ++attempts == 1 ? null : [self],
      pending: () async => [],
      customers: (_) async => [],
    );
    await service.ensureLoaded();
    expect(service.loadError, isNotNull);
    await service.ensureLoaded();
    expect(service.isTeamLoaded, isTrue);
    expect(service.loadError, isNull);
  });
}
