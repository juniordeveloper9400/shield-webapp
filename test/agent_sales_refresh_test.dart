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
  AgentLevel level = AgentLevel.district,
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
