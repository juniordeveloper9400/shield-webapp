import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/orders/order_detail_sections.dart';
import 'package:shield/module/orders/order_track_screen.dart';
import 'package:shield/module/orders/orders_screen.dart';
import 'package:shield/module/orders/purchase_service.dart';

/// The picture-bearing cards this feature added: a thumbnail on each My
/// Orders card, and "Items in this order" on a standard order's tracker.
///
/// None of these can reach `backend/api` under `flutter test` (`BackendHttp.
/// isConfigured` is false in this environment by design — see its own doc),
/// and the orders these tests build with `PurchaseService.record` carry no
/// `backendId` either — the exact "placed this session, not yet heard back
/// from the backend" case every one of these widgets is documented to
/// tolerate. What is asserted here is that tolerance: the surrounding card
/// renders in full and nothing crashes or hangs waiting on a fetch that was
/// never going to land — not the picture itself, which needs a live backend
/// (covered instead by `commerce.e2e-spec.ts`'s own `/orders/:id/items` and
/// `/orders/:id/prescriptions` tests).
void main() {
  final service = PurchaseService.instance;

  setUp(service.clear);
  tearDown(service.clear);

  Future<void> pumpOrders(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: OrdersScreen()));
    await tester.pumpAndSettle();
  }

  group('the My Orders list card', () {
    testWidgets('shows a standard order in full, thumbnail included', (
      tester,
    ) async {
      service.record(
        id: 'SH-THUMB-1',
        placedOn: '20 Sep 2026',
        itemCount: 2,
        mrpTotal: 500,
        paidTotal: 450,
      );

      await pumpOrders(tester);

      expect(find.text('SH-THUMB-1'), findsOneWidget);
      expect(find.text('Placed on 20 Sep 2026  ·  2 items'), findsOneWidget);
      expect(find.text('₹450'), findsOneWidget);
      // No picture ever arrives (no backend in this environment), so the
      // fallback icon on the thumbnail is what stands in for it.
      expect(find.byIcon(Icons.medication_outlined), findsOneWidget);
    });

    testWidgets('shows a prescription order in full, its own fallback icon', (
      tester,
    ) async {
      service.record(
        id: 'RX-THUMB-1',
        placedOn: '20 Sep 2026',
        itemCount: 1,
        mrpTotal: 0,
        paidTotal: 0,
        kind: OrderKind.prescription,
      );

      await pumpOrders(tester);

      expect(find.text('RX-THUMB-1'), findsOneWidget);
      expect(find.text('Price on confirmation'), findsOneWidget);
      expect(find.byIcon(Icons.description_rounded), findsOneWidget);
    });

    testWidgets('a card for each order, never mixing up their thumbnails', (
      tester,
    ) async {
      service.record(
        id: 'SH-THUMB-2',
        placedOn: '20 Sep 2026',
        itemCount: 1,
        mrpTotal: 100,
        paidTotal: 100,
      );
      service.record(
        id: 'RX-THUMB-2',
        placedOn: '19 Sep 2026',
        itemCount: 1,
        mrpTotal: 0,
        paidTotal: 0,
        kind: OrderKind.prescription,
      );

      await pumpOrders(tester);

      expect(find.text('SH-THUMB-2'), findsOneWidget);
      expect(find.text('RX-THUMB-2'), findsOneWidget);
      expect(find.byIcon(Icons.medication_outlined), findsOneWidget);
      expect(find.byIcon(Icons.description_rounded), findsOneWidget);
    });
  });

  group('the Track order screen', () {
    Future<void> pumpTrack(WidgetTester tester, Purchase order) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: OrderTrackScreen(order: order)));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'never shows "Items in this order" for a standard order with nothing fetched, and never crashes',
      (tester) async {
        final order = service.record(
          id: 'SH-ITEMS-1',
          placedOn: '20 Sep 2026',
          itemCount: 2,
          mrpTotal: 300,
          paidTotal: 300,
        );

        await pumpTrack(tester, order);

        // Present in the tree — it is what will show real items once a
        // backend answers — but rendering nothing (a zero-size box) while
        // that fetch has not landed, which is why it has to be looked for
        // with skipOffstage off: Flutter's default finder treats a
        // zero-size widget as offstage.
        expect(
          find.byType(OrderItemsCard, skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text('Items in this order'), findsNothing);
        expect(find.text('Item in this order'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'still shows the prescription-uploaded card for a prescription order, unchanged',
      (tester) async {
        final order = service.record(
          id: 'RX-ITEMS-1',
          placedOn: '20 Sep 2026',
          itemCount: 1,
          mrpTotal: 0,
          paidTotal: 0,
          kind: OrderKind.prescription,
        );

        await pumpTrack(tester, order);

        expect(find.text('Prescription uploaded'), findsOneWidget);
        expect(find.byType(OrderItemsCard), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
