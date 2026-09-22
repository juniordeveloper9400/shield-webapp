import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shield/data/backend/persona_repository.dart';
import 'package:shield/module/persona/persona_service.dart';

const agent = PersonaSnapshot(agent: RemoteAgent(
  id: '15', code: 'SHD-WRD-015', name: 'Test Agent', phone: '9000000002',
  level: 'ward', active: true, area: 'Ward', areaId: null, earned: 0,
  redeemed: 0, personalSales: 0, parentId: null,
));

void main() {
  final service = PersonaService.instance;
  setUp(service.reset);
  tearDown(service.reset);

  test('failed initial lookup does not classify converted user as member', () async {
    service.debugSetLoader((_) async => throw StateError('offline'));
    await service.reload('9000000002');
    expect(service.isResolved, isFalse);
    expect(service.error, isNotNull);
    service.debugSetLoader((_) async => agent);
    await service.reload('9000000002');
    expect(service.isAgent, isTrue);
    expect(service.error, isNull);
  });

  test('confirmed role survives a failed refresh', () async {
    service.debugSetLoader((_) async => agent);
    await service.reload('9000000002');
    service.debugSetLoader((_) async => throw StateError('offline'));
    await service.reload('9000000002');
    expect(service.isAgent, isTrue);
    expect(service.isResolved, isTrue);
  });

  test('account switch queues its lookup and ignores old account response', () async {
    final first = Completer<PersonaSnapshot>();
    service.debugSetLoader((phone) => phone == '9000000002'
      ? first.future : Future.value(PersonaSnapshot.none));
    final pending = service.reload('9000000002');
    await service.reload('9000000003');
    first.complete(agent);
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(service.isResolved, isTrue);
    expect(service.isConverted, isFalse);
  });
}
