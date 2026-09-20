import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/order_repository.dart';
import 'package:shield/module/orders/bill_invoice.dart';
import 'package:shield/module/orders/order_bill_screen.dart';
import 'package:shield/module/orders/purchase_service.dart';

/// A real 1×1 PNG, standing in for the picture the console attaches.
const _picture =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

/// What `GET /v1/member/orders/:id/bill` returns: the bill's own columns plus
/// the `invoice` block (`order.service.ts buildInvoice`). Money is the
/// `numeric` text the database uses.
Map<String, dynamic> _response({
  String amount = '181.00',
  String status = 'PENDING',
  Map<String, dynamic>? invoice,
}) => {
  'id': 1,
  'orderId': 7,
  'image': _picture,
  'amount': amount,
  'status': status,
  'paidAt': null,
  'sentAt': '2026-09-19T06:30:00.000Z',
  'invoice':
      invoice ??
      {
        'number': 'RX-MU8BWHGBD56A',
        'placedAt': '2026-09-18T04:00:00.000Z',
        'status': 'PROCESSING',
        'fulfillmentType': 'HOME_DELIVERY',
        'paymentStatus': 'PENDING',
        'paidAt': null,
        'paidTotal': '0.00',
        'deliveryFee': '0.00',
        'customer': {'name': 'Asaruuuu', 'phone': '8137922524'},
        'store': {
          'name': 'SHIELD Melattur',
          'area': 'Melattur',
          'city': 'Malappuram',
          'state': 'Kerala',
          'pincode': '679325',
          'phone': '9000000001',
        },
        'deliveryAddress': {
          'house': 'hhha',
          'area': 'jaja',
          'landmark': '',
          'city': 'Malappuram',
          'state': 'Kerala',
          'pincode': '679325',
        },
        'lines': [
          {'name': 'Paracetamol 500mg', 'pack': 'Strip of 15', 'unitPrice': '30.50', 'qty': 2},
          {'name': 'Cetirizine 10mg', 'pack': '', 'unitPrice': '120.00', 'qty': 1},
        ],
      },
};

Purchase _order({
  String? image,
  BillInvoice? invoice,
  int? amount = 181,
  OrderPaymentStatus? billStatus = OrderPaymentStatus.pending,
}) => Purchase(
  id: 'RX-MU8BWHGBD56A',
  placedOn: '19 Sep 2026, 12:00 AM',
  itemCount: 2,
  mrpTotal: 0,
  paidTotal: 0,
  status: OrderStatus.processing,
  billAmount: amount,
  billStatus: billStatus,
  billImage: image,
  billInvoice: invoice,
  billedAt: DateTime(2026, 9, 19),
);

void main() {
  group('reading the API response', () {
    test('maps the invoice block: items in exact paise, store, customer, '
        'address and status', () {
      final invoice = OrderRepository.invoiceFromBill(
        _response(),
        sentAt: DateTime.utc(2026, 9, 19, 6, 30),
      )!;

      expect(invoice.number, 'RX-MU8BWHGBD56A');
      expect(invoice.customerName, 'Asaruuuu');
      expect(invoice.customerPhone, '8137922524');
      expect(invoice.storeName, 'SHIELD Melattur');
      expect(invoice.storeAddress, 'Melattur, Malappuram, Kerala, 679325');
      expect(invoice.storePhone, '9000000001');
      expect(invoice.fulfillment, 'Home delivery');
      expect(invoice.deliveryAddress, 'hhha, jaja, Malappuram, Kerala, 679325');
      expect(invoice.orderStatus, 'In progress');
      expect(invoice.paid, isFalse);
      expect(invoice.lines.length, 2);
      expect(invoice.lines.first.unitPaise, 3050);
      expect(invoice.lines.first.qty, 2);
      expect(invoice.lines.first.pack, 'Strip of 15');
      // 2 × 30.50 + 1 × 120.00, and the saved bill agrees.
      expect(invoice.subtotalPaise, 18100);
      expect(invoice.totalPaise, 18100);
      expect(invoice.adjustmentPaise, 0);
    });

    test('a paid, delivered pickup order reads as such', () {
      final invoice = OrderRepository.invoiceFromBill(
        _response(
          status: 'PAID',
          invoice: {
            'number': 'SHD-1',
            'placedAt': '2026-09-18T04:00:00.000Z',
            'status': 'DELIVERED',
            'fulfillmentType': 'STORE_PICKUP',
            'paymentStatus': 'PAID',
            'paidTotal': '181.00',
            'deliveryFee': '0.00',
            'customer': null,
            'store': null,
            'deliveryAddress': null,
            'lines': [],
          },
        ),
      )!;

      expect(invoice.paid, isTrue);
      expect(invoice.orderStatus, 'Completed');
      expect(invoice.fulfillment, 'Store pickup');
      expect(invoice.storeName, 'SHIELD Pharmacy');
      expect(invoice.hasItems, isFalse);
      expect(invoice.totalPaise, 18100);
    });

    test('returns null when the backend sent no invoice block', () {
      final response = _response()..remove('invoice');

      expect(OrderRepository.invoiceFromBill(response), isNull);
    });
  });

  group('BillInvoice', () {
    test('lists a delivery fee only when it reconciles to the total', () {
      const lines = [InvoiceLine(name: 'A', qty: 1, unitPaise: 10000)];

      expect(
        BillInvoice.compose(
          number: 'X',
          lines: lines,
          billPaise: 14000,
          deliveryFeePaise: 4000,
        ).deliveryFeePaise,
        4000,
      );
      expect(
        BillInvoice.compose(
          number: 'X',
          lines: lines,
          billPaise: 10000,
          deliveryFeePaise: 4000,
        ).deliveryFeePaise,
        0,
      );
    });

    test('prints paise with Indian grouping', () {
      expect(formatPaise(3050), '₹30.50');
      expect(formatPaise(12345600), '₹1,23,456.00');
      expect(formatPaise(-500), '-₹5.00');
    });
  });

  group('the bill screen', () {
    Future<void> pump(WidgetTester tester, Purchase order) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: OrderBillScreen(order: order)));
      await tester.pumpAndSettle();
    }

    final invoice = OrderRepository.invoiceFromBill(
      _response(),
      sentAt: DateTime.utc(2026, 9, 19, 6, 30),
    )!;

    testWidgets('shows the bill picture and the itemised invoice', (
      tester,
    ) async {
      await pump(tester, _order(image: _picture, invoice: invoice));

      expect(find.text('Bill from the store'), findsOneWidget);
      expect(find.text('INVOICE'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('₹30.50'), findsOneWidget);
      expect(find.text('₹61.00'), findsOneWidget);
      expect(find.text('Cetirizine 10mg'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('SHIELD Melattur'), findsOneWidget);
      expect(find.text('PAYMENT PENDING'), findsOneWidget);
    });

    testWidgets('a priced bill with no picture shows the invoice instead of '
        'waiting forever for a picture', (tester) async {
      await pump(tester, _order(invoice: invoice));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Bill from the store'), findsNothing);
      expect(find.text('INVOICE'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
    });

    testWidgets('when the backend gave no invoice it still prints the total '
        'and says the items were not listed', (tester) async {
      await pump(tester, _order(image: _picture));

      expect(find.text('INVOICE'), findsOneWidget);
      expect(find.textContaining('did not list the items'), findsOneWidget);
      expect(find.text('₹181.00'), findsWidgets);
    });

    testWidgets('an order with no bill says so', (tester) async {
      await pump(tester, _order(amount: null, billStatus: null));

      expect(find.text('No bill yet'), findsOneWidget);
      expect(find.text('INVOICE'), findsNothing);
    });
  });
}
