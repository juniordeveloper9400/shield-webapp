import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/agent/agent_model.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/agent/agent_customer.dart';
import 'package:shield/module/privilege/privilege_tier.dart';

Agent agent(String id, {String? parent, int sales = 0}) => Agent(
  id: id,
  name: id,
  phone: id,
  agentCode: id,
  level: AgentLevel.district,
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
