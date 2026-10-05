import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/orders/purchase_service.dart';

Purchase _order({
  OrderStatus status = OrderStatus.processing,
  DateTime? storeContactedAt,
  DateTime? reviewedAt,
  DateTime? convertedToBillAt,
  int? billAmount,
  OrderPaymentStatus paymentStatus = OrderPaymentStatus.pending,
}) => Purchase(
  id: 'SHD-1',
  placedOn: '05 Oct 2026',
  itemCount: 1,
  mrpTotal: 100,
  paidTotal: 100,
  status: status,
  storeContactedAt: storeContactedAt,
  reviewedAt: reviewedAt,
  convertedToBillAt: convertedToBillAt,
  billAmount: billAmount,
  paymentStatus: paymentStatus,
);

void main() {
  group('a member may cancel an order only until the store starts on it', () {
    test('an untouched order can be cancelled', () {
      expect(_order().canMemberCancel, isTrue);
    });

    test('reviewed, contacted, billed, priced or paid orders are locked', () {
      expect(_order(reviewedAt: DateTime(2026, 10, 5)).canMemberCancel, isFalse);
      expect(
        _order(storeContactedAt: DateTime(2026, 10, 5)).canMemberCancel,
        isFalse,
      );
      expect(
        _order(convertedToBillAt: DateTime(2026, 10, 5)).canMemberCancel,
        isFalse,
      );
      expect(_order(billAmount: 100).canMemberCancel, isFalse);
      expect(
        _order(paymentStatus: OrderPaymentStatus.paid).canMemberCancel,
        isFalse,
      );
    });

    test('an order already out for delivery, delivered or cancelled is locked', () {
      for (final status in [
        OrderStatus.outForDelivery,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ]) {
        expect(_order(status: status).canMemberCancel, isFalse);
      }
    });
  });

  group('a member may delete a prescription only until its order is touched', () {
    LinkedOrder link({
      OrderStatus status = OrderStatus.processing,
      DateTime? reviewedAt,
      bool billed = false,
    }) => LinkedOrder(
      id: 1,
      code: 'RX-1',
      status: status,
      reviewedAt: reviewedAt,
      billed: billed,
    );

    test('untouched and cancelled orders allow it', () {
      expect(link().allowsMemberDelete, isTrue);
      expect(link(status: OrderStatus.cancelled).allowsMemberDelete, isTrue);
    });

    test('processed, billed and completed orders do not', () {
      expect(link(reviewedAt: DateTime(2026, 10, 5)).allowsMemberDelete, isFalse);
      expect(link(billed: true).allowsMemberDelete, isFalse);
      expect(link(status: OrderStatus.delivered).allowsMemberDelete, isFalse);
    });
  });
}
