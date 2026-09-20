import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/orders/order_track_screen.dart';
import 'package:shield/module/orders/purchase_service.dart';

void main() {
  testWidgets(
    'open tracker follows the refreshed stage and removes listener on close',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = PurchaseService.instance;
      addTearDown(service.clear);
      Purchase order(
        OrderStatus status, {
        DateTime? contactedAt,
        OrderPaymentStatus? billStatus,
        int? billAmount,
      }) => Purchase(
        id: 'LIVE-ORDER',
        placedOn: '19 Sep 2026',
        itemCount: 1,
        mrpTotal: 100,
        paidTotal: 0,
        status: status,
        storeContactedAt: contactedAt,
        billStatus: billStatus,
        billAmount: billAmount,
      );
      final original = order(OrderStatus.processing);
      service.record(
        id: original.id,
        placedOn: original.placedOn,
        itemCount: 1,
        mrpTotal: 100,
        paidTotal: 0,
      );
      await tester.pumpWidget(
        MaterialApp(home: OrderTrackScreen(order: original)),
      );
      await tester.pumpAndSettle();
      // Only the four member stages are ever shown — no Processing /
      // Out for delivery / Delivered.
      for (final title in ['Placed', 'Store contact', 'Billed', 'Complete']) {
        expect(find.text(title), findsWidgets);
      }
      expect(find.text('Processing'), findsNothing);
      expect(find.text('Out for delivery'), findsNothing);
      expect(find.text('Delivered'), findsNothing);

      // Staff press Call / WhatsApp in the admin console.
      service.updateOne(
        order(OrderStatus.processing, contactedAt: DateTime(2026, 9, 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('20 Sep'), findsOneWidget);

      // The store sends a bill.
      service.updateOne(
        order(
          OrderStatus.processing,
          contactedAt: DateTime(2026, 9, 20),
          billStatus: OrderPaymentStatus.pending,
          billAmount: 100,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Billed'), findsWidgets);

      service.updateOne(order(OrderStatus.cancelled));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      service.updateOne(order(OrderStatus.delivered));
      await tester.pump(const Duration(seconds: 31));
      expect(tester.takeException(), isNull);
    },
  );
}
