import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/home/customer_reviews.dart';
import 'package:shield/module/home/customer_reviews_service.dart';

void main() {
  final service = CustomerReviewsService.instance;
  const clip = CustomerReviewItem(
    id: 'published',
    name: 'Customer',
    video: 'https://example.com/review.mp4',
  );
  setUp(service.debugReset);
  tearDown(service.debugReset);

  test('newly published clips appear after an empty result', () async {
    var rows = <CustomerReviewItem>[];
    service.debugSetLoader(() async => rows);
    await service.ensureLoaded();
    expect(service.status, CustomerReviewsStatus.empty);
    rows = [clip];
    await service.refresh();
    expect(service.items, [clip]);
    expect(service.status, CustomerReviewsStatus.ready);
  });

  test('failed initial loads can retry without restarting', () async {
    var attempts = 0;
    service.debugSetLoader(() async => ++attempts == 1 ? null : [clip]);
    await service.ensureLoaded();
    expect(service.status, CustomerReviewsStatus.error);
    await service.ensureLoaded();
    expect(service.items, [clip]);
    expect(attempts, 2);
  });

  test(
    'temporary failure preserves clips but successful unpublish removes them',
    () async {
      service.debugSeed([clip]);
      service.debugSetLoader(() async => null);
      await service.refresh();
      expect(service.items, [clip]);
      service.debugSetLoader(() async => []);
      await service.refresh();
      expect(service.items, isEmpty);
      expect(service.status, CustomerReviewsStatus.empty);
    },
  );

  test('overlapping refreshes share a request', () async {
    final response = Completer<List<CustomerReviewItem>?>();
    var calls = 0;
    service.debugSetLoader(() {
      calls++;
      return response.future;
    });
    final first = service.refresh();
    final second = service.refresh();
    expect(calls, 1);
    response.complete([clip]);
    await Future.wait([first, second]);
    expect(service.items, [clip]);
  });
}
