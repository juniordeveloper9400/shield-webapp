import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/orders/purchase_service.dart';

Purchase _discounted(OrderPaymentStatus? bill) => Purchase(
  id: 'SHD-100482',
  placedOn: '05 Oct 2026',
  itemCount: 1,
  mrpTotal: 0,
  paidTotal: 0,
  status: OrderStatus.processing,
  billAmount: 400,
  billStatus: bill,
  billDiscount: 99,
);

void main() {
  setUp(() {
    PurchaseService.instance
      ..clear()
      ..seedSampleOrders();
  });

  test('a discount on a bill that is only sent does not count as an earning', () {
    PurchaseService.instance.updateOne(_discounted(OrderPaymentStatus.pending));
    expect(PurchaseService.instance.billSavedTotal, 0);
    expect(PurchaseService.instance.billDiscounted, isEmpty);
  });

  test('it counts the moment the bill is paid (after the OTP debit)', () {
    PurchaseService.instance.updateOne(_discounted(OrderPaymentStatus.pending));
    PurchaseService.instance.updateOne(_discounted(OrderPaymentStatus.paid));
    expect(PurchaseService.instance.billSavedTotal, 99);
  });
}
