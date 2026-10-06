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

  testWidgets('a failed first lookup retries by itself and the agent card appears',
      (tester) async {
    var calls = 0;
    service.debugSetLoader((_) async {
      calls++;
      if (calls == 1) throw TimeoutException('cold backend');
      return agent;
    });
    await service.reload('9000000002');
    expect(service.isResolved, isFalse);
    expect(service.error, contains('Could not reach the server'));

    await tester.pump(const Duration(seconds: 4));
    expect(calls, 2);
    expect(service.isAgent, isTrue);
    expect(service.error, isNull);
  });

  testWidgets('a lost session is not retried blindly and says to sign in again',
      (tester) async {
    var calls = 0;
    service.debugSetLoader((_) async {
      calls++;
      throw StateError('no session');
    });
    await service.reload('9000000002');
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 1);
    expect(service.error, contains('sign in again'));
  });
}
