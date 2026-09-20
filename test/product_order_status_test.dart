import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/orders/order_track.dart';
import 'package:shield/module/orders/purchase_service.dart';

void main() {
  Purchase order(
    OrderStatus status, {
    int paid = 0,
    DateTime? contactedAt,
    OrderPaymentStatus? billStatus,
    int? billAmount,
    OrderKind kind = OrderKind.standard,
  }) => Purchase(
    id: 'ADMIN-STATUS-1',
    placedOn: '19 Sep 2026',
    itemCount: 1,
    mrpTotal: 100,
    paidTotal: paid,
    status: status,
    kind: kind,
    storeContactedAt: contactedAt,
    billStatus: billStatus,
    billAmount: billAmount,
  );

  String current(OrderTrack track) =>
      track.steps.singleWhere((s) => s.state == TrackState.current).title;

  test('every order shows exactly the four member stages', () {
    final track = OrderTrack(order(OrderStatus.processing));
    expect(track.steps.map((s) => s.title), [
      'Placed',
      'Store contact',
      'Billed',
      'Complete',
    ]);
  });

  test('a new order stays at Placed whatever it cost or was paid', () {
    for (final paid in [0, 100]) {
      final track = OrderTrack(order(OrderStatus.processing, paid: paid));
      expect(track.stage, OrderStage.placed);
      expect(current(track), 'Placed');
      expect(track.deliveryWindow, isNull);
      expect(track.steps.skip(1).every((s) => s.detail == null), isTrue);
      expect(
        track.steps.skip(1).every((s) => s.state == TrackState.upcoming),
        isTrue,
      );
    }
  });

  test('the store contacting the member moves the order to Store contact', () {
    final track = OrderTrack(
      order(OrderStatus.processing, contactedAt: DateTime(2026, 9, 20, 10)),
    );
    expect(track.stage, OrderStage.storeContact);
    expect(current(track), 'Store contact');
    expect(track.steps.first.state, TrackState.done);
    expect(track.steps[1].detail, '20 Sep');
    expect(track.steps[2].state, TrackState.upcoming);
  });

  test('a bill moves the order to Billed, with or without a contact stamp', () {
    for (final contacted in [null, DateTime(2026, 9, 20)]) {
      final track = OrderTrack(
        order(
          OrderStatus.processing,
          contactedAt: contacted,
          billStatus: OrderPaymentStatus.pending,
          billAmount: 450,
        ),
      );
      expect(track.stage, OrderStage.billed);
      expect(current(track), 'Billed');
      // Everything before it reads as done, never stuck on a skipped stage.
      expect(
        track.steps.take(2).every((s) => s.state == TrackState.done),
        isTrue,
      );
      expect(track.subhead, '₹450 · Payment pending');
    }
    final paid = OrderTrack(
      order(
        OrderStatus.processing,
        billStatus: OrderPaymentStatus.paid,
        billAmount: 450,
      ),
    );
    expect(paid.subhead, '₹450 · Paid');
  });

  test('completing the order clears every stage', () {
    final track = OrderTrack(
      order(
        OrderStatus.delivered,
        billStatus: OrderPaymentStatus.paid,
        billAmount: 450,
      ),
    );
    expect(track.stage, OrderStage.complete);
    expect(track.steps.every((s) => s.state == TrackState.done), isTrue);
    expect(track.headline, startsWith('Order complete'));
  });

  test('an order out for delivery counts as at least Store contact', () {
    expect(
      OrderTrack(order(OrderStatus.outForDelivery)).stage,
      OrderStage.storeContact,
    );
    expect(
      OrderTrack(
        order(
          OrderStatus.outForDelivery,
          billStatus: OrderPaymentStatus.pending,
          billAmount: 100,
        ),
      ).stage,
      OrderStage.billed,
    );
  });

  test('a cancelled order is drawn as placed then cancelled', () {
    final cancelled = OrderTrack(
      order(
        OrderStatus.cancelled,
        contactedAt: DateTime(2026, 9, 20),
        billStatus: OrderPaymentStatus.pending,
        billAmount: 100,
      ),
    );
    expect(cancelled.stage, OrderStage.cancelled);
    expect(cancelled.steps.length, 2);
    expect(cancelled.steps.last.title, 'Cancelled');
  });

  test('only an open prescription order shows a delivery window', () {
    expect(
      OrderTrack(
        order(OrderStatus.processing, kind: OrderKind.prescription),
      ).deliveryWindow,
      isNotNull,
    );
    expect(
      OrderTrack(
        order(OrderStatus.delivered, kind: OrderKind.prescription),
      ).deliveryWindow,
      isNull,
    );
  });

  group('Purchase.fromRow / copyWith', () {
    Map<String, dynamic> row({Object? contacted}) => {
      'code': 'SHD-1',
      'placedOn': '2026-09-19T10:00:00.000Z',
      'itemCount': 1,
      'mrpTotal': '100.00',
      'paidTotal': '0.00',
      'status': 'PROCESSING',
      'kind': 'STANDARD',
      'id': 7,
      'fulfillmentType': 'HOME_DELIVERY',
      'paymentStatus': 'PENDING',
      'storeContactedAt': contacted,
    };

    test('reads storeContactedAt from the orders list row', () {
      final contacted = Purchase.fromRow(
        row(contacted: '2026-09-20T10:15:00.000Z'),
      );
      expect(contacted.storeContactedAt, isNotNull);
      expect(
        contacted.storeContactedAt!.toUtc(),
        DateTime.utc(2026, 9, 20, 10, 15),
      );
      expect(contacted.stage, OrderStage.storeContact);
    });

    test('a null or missing storeContactedAt leaves the order at Placed', () {
      expect(Purchase.fromRow(row()).stage, OrderStage.placed);
      final missing = row()..remove('storeContactedAt');
      expect(Purchase.fromRow(missing).stage, OrderStage.placed);
    });

    test('merging in the bill image keeps the contact stamp', () {
      final contacted = Purchase.fromRow(
        row(contacted: '2026-09-20T10:15:00.000Z'),
      );
      final merged = contacted.copyWith(
        billImage: 'data:image/png;base64,AA==',
      );
      expect(merged.storeContactedAt, contacted.storeContactedAt);
    });
  });
}
