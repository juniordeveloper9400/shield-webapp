import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/orders/order_track.dart';
import 'package:shield/module/orders/purchase_service.dart';

void main() {
  Purchase order(OrderStatus status, {int paid = 0}) => Purchase(
    id: 'ADMIN-STATUS-1',
    placedOn: '19 Sep 2026',
    itemCount: 1,
    mrpTotal: 100,
    paidTotal: paid,
    status: status,
  );

  test('checkout price and payment never imply admin billing or packing', () {
    for (final paid in [0, 100]) {
      final track = OrderTrack(order(OrderStatus.processing, paid: paid));
      expect(
        track.steps.singleWhere((s) => s.state == TrackState.current).title,
        'Processing',
      );
      expect(track.headline, 'Your order is being processed by the store.');
      expect(track.deliveryWindow, isNull);
      expect(track.steps.skip(1).every((s) => s.detail == null), isTrue);
    }
  });

  test('dispatch, delivery and cancellation follow the admin status', () {
    final dispatched = OrderTrack(order(OrderStatus.outForDelivery));
    expect(
      dispatched.steps.singleWhere((s) => s.state == TrackState.current).title,
      'Out for delivery',
    );
    final delivered = OrderTrack(order(OrderStatus.delivered));
    expect(delivered.steps.every((s) => s.state == TrackState.done), isTrue);
    final cancelled = OrderTrack(order(OrderStatus.cancelled));
    expect(cancelled.steps.last.title, 'Cancelled');
    expect(cancelled.steps.length, 2);
  });
}
