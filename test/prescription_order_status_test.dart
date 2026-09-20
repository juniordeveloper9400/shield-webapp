import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/prescription_repository.dart';
import 'package:shield/module/orders/purchase_service.dart';
import 'package:shield/module/patients/patient_book.dart';
import 'package:shield/module/prescription/prescription_record.dart';
import 'package:shield/module/prescription/upload_prescription_screen.dart';

final _patient = Patient(
  id: 'p1',
  name: 'Test Patient',
  phone: '9000000000',
  dob: DateTime(1990, 1, 1),
  gender: PatientGender.male,
  relation: PatientRelation.self,
);

LinkedOrder _link({
  String status = 'PROCESSING',
  DateTime? contacted,
  bool billed = false,
}) => LinkedOrder(
  id: 7,
  code: 'RX-MU8BWHGBD56A',
  status: OrderStatus.values.firstWhere(
    (s) => switch (s) {
      OrderStatus.delivered => status == 'DELIVERED',
      OrderStatus.outForDelivery => status == 'OUT_FOR_DELIVERY',
      OrderStatus.cancelled => status == 'CANCELLED',
      OrderStatus.processing => status == 'PROCESSING',
    },
  ),
  storeContactedAt: contacted,
  billed: billed,
);

void main() {
  final book = PrescriptionBook.instance;

  setUp(() {
    book.reset();
    PurchaseService.instance.clear();
  });
  tearDown(() {
    book.reset();
    PurchaseService.instance.clear();
  });

  group('the order stage rule', () {
    test('cancelled and delivered come straight from the status', () {
      expect(
        OrderStage.derive(status: OrderStatus.cancelled, billed: true, contacted: true),
        OrderStage.cancelled,
      );
      expect(
        OrderStage.derive(status: OrderStatus.delivered, billed: false, contacted: false),
        OrderStage.complete,
      );
    });

    test('below that, the furthest signal wins: bill, then contact, then placed', () {
      expect(
        OrderStage.derive(status: OrderStatus.processing, billed: true, contacted: false),
        OrderStage.billed,
      );
      expect(
        OrderStage.derive(status: OrderStatus.processing, billed: false, contacted: true),
        OrderStage.storeContact,
      );
      expect(
        OrderStage.derive(status: OrderStatus.processing, billed: false, contacted: false),
        OrderStage.placed,
      );
    });

    test('an order already out for delivery counts as at least store contact', () {
      expect(
        OrderStage.derive(status: OrderStatus.outForDelivery, billed: false, contacted: false),
        OrderStage.storeContact,
      );
    });

    test('Track order and a prescription card agree about the same order', () {
      const purchase = Purchase(
        id: 'RX-1',
        placedOn: 'x',
        itemCount: 1,
        mrpTotal: 0,
        paidTotal: 0,
        status: OrderStatus.processing,
        billStatus: OrderPaymentStatus.pending,
      );

      expect(purchase.stage, OrderStage.billed);
      expect(_link(billed: true).stage, purchase.stage);
    });
  });

  group('reading the order off a prescription row', () {
    test('maps status, contact stamp and bill', () {
      final link = LinkedOrder.fromJson({
        'id': 7,
        'code': 'RX-MU8BWHGBD56A',
        'status': 'PROCESSING',
        'storeContactedAt': '2026-09-20T10:15:00.000Z',
        'billed': true,
      })!;

      expect(link.id, 7);
      expect(link.code, 'RX-MU8BWHGBD56A');
      expect(link.status, OrderStatus.processing);
      expect(link.storeContactedAt!.toUtc(), DateTime.utc(2026, 9, 20, 10, 15));
      expect(link.billed, isTrue);
      expect(link.stage, OrderStage.billed);
    });

    test('is null for a prescription that was never ordered, or a malformed block', () {
      expect(LinkedOrder.fromJson(null), isNull);
      expect(LinkedOrder.fromJson({'id': null, 'code': 'X'}), isNull);
      expect(LinkedOrder.fromJson({'id': 3, 'code': ''}), isNull);
      expect(LinkedOrder.fromJson('nope'), isNull);
    });

    test('the card the repository builds carries the order', () {
      final card = PrescriptionRepository.cardFromRow({
        'id': 44,
        'code': 'RX-0003',
        'status': 'READ',
        'medicines': [],
        'order': {
          'id': 9,
          'code': 'RX-ABC',
          'status': 'DELIVERED',
          'storeContactedAt': null,
          'billed': true,
        },
      });

      expect(card.order?.code, 'RX-ABC');
      expect(card.order?.stage, OrderStage.complete);

      final none = PrescriptionRepository.cardFromRow({
        'id': 45,
        'status': 'AWAITING_REVIEW',
        'order': null,
      });
      expect(none.order, isNull);
    });

    test('a refresh folds the order onto the record, and a later one moves it on', () {
      final record = book.add(patient: _patient, fileName: 's.jpg');

      book.applyIntakeCard(record.id, medicines: const [], order: _link());
      expect(record.order?.stage, OrderStage.placed);

      book.applyIntakeCard(
        record.id,
        medicines: const [],
        order: _link(billed: true),
      );
      expect(record.order?.stage, OrderStage.billed);
    });
  });

  group('the card on Your prescriptions', () {
    Future<void> pump(WidgetTester tester) async {
      // Wider than a phone: the test font (Ahem) is one em per glyph, which
      // overflows the footer's Delete / Reorder row that a real font fits.
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: UploadPrescriptionScreen()),
      );
      await tester.pumpAndSettle();
    }

    PrescriptionRecord ordered({LinkedOrder? link}) {
      final record = book.add(patient: _patient, fileName: 'script.jpg');
      book.markOrdered(record.id);
      if (link != null) {
        book.applyIntakeCard(record.id, medicines: const [], order: link);
      }
      return record;
    }

    String chip(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey('order-stage-chip'))).data!;

    testWidgets('shows nothing for a prescription that has not been ordered', (
      tester,
    ) async {
      book.add(patient: _patient, fileName: 'script.jpg');

      await pump(tester);

      expect(find.text('Order status'), findsNothing);
    });

    testWidgets('an order just placed reads Placed even before its link arrives', (
      tester,
    ) async {
      ordered();

      await pump(tester);

      expect(find.text('Order status'), findsOneWidget);
      expect(chip(tester), 'Placed');
      expect(find.textContaining('The pharmacist will call you soon'), findsOneWidget);
      // No order code yet, and nothing to open.
      expect(find.text('Track order'), findsNothing);
    });

    testWidgets('follows the order through every stage', (tester) async {
      final cases = <(LinkedOrder, String, String)>[
        (_link(), 'Placed', 'We have your order'),
        (
          _link(contacted: DateTime(2026, 9, 20)),
          'Store contact',
          'The pharmacist has contacted you',
        ),
        (_link(billed: true), 'Billed', 'Your bill is ready'),
        (_link(status: 'DELIVERED', billed: true), 'Complete', 'Your order is complete'),
        (_link(status: 'CANCELLED'), 'Cancelled', 'This order was cancelled'),
      ];

      for (final (link, stage, detail) in cases) {
        book.reset();
        ordered(link: link);
        await pump(tester);

        expect(chip(tester), stage, reason: stage);
        expect(find.textContaining(detail), findsOneWidget, reason: stage);
        expect(find.text('RX-MU8BWHGBD56A'), findsOneWidget, reason: stage);
      }
    });

    testWidgets('a live order shows the four-step track; a cancelled one drops it', (
      tester,
    ) async {
      ordered(link: _link(contacted: DateTime(2026, 9, 20)));
      await pump(tester);

      // The chip says Store contact once; the track repeats it as a step label.
      for (final label in ['Placed', 'Store contact', 'Billed', 'Complete']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Billed'), findsOneWidget);

      book.reset();
      ordered(link: _link(status: 'CANCELLED'));
      await pump(tester);

      expect(find.text('Billed'), findsNothing);
      expect(find.text('Complete'), findsNothing);
    });

    testWidgets('prefers the loaded order book over what the prescription reported', (
      tester,
    ) async {
      // The prescription row still says "placed", but the order book — refreshed
      // more often — already has the order delivered.
      ordered(link: _link());
      PurchaseService.instance.record(
        id: 'RX-MU8BWHGBD56A',
        placedOn: '19 Sep 2026',
        itemCount: 1,
        mrpTotal: 0,
        paidTotal: 0,
        status: OrderStatus.delivered,
        kind: OrderKind.prescription,
      );

      await pump(tester);

      expect(chip(tester), 'Complete');
      expect(find.text('Track order'), findsOneWidget);
    });

    testWidgets('reads in Malayalam when the language is switched', (
      tester,
    ) async {
      ordered(link: _link(billed: true));
      await pump(tester);

      await tester.tap(find.text('മ'));
      await tester.pumpAndSettle();

      expect(find.text('ഓർഡർ നില'), findsOneWidget);
      expect(chip(tester), 'ബിൽ ചെയ്തു');
    });
  });
}
