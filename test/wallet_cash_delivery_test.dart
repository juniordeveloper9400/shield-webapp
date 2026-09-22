// Smoke coverage for the wallet/cash checkout port (migration 0031): this
// tree has no existing widget-test harness for the checkout screens (see
// `test/backend_http_test.dart` / `test/backend_session_test.dart` — both
// plumbing, not UI), so rather than inventing a whole new widget-test setup
// from scratch, this sticks to the plain-Dart model logic that changed:
// the payment method list, the fulfillment enum, the wallet's new debit
// path, and the order-detail bill's "Pay now" gate.
import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/checkout/fulfillment_type.dart';
import 'package:shield/module/checkout/payment_method.dart';
import 'package:shield/module/orders/order_detail_sections.dart';
import 'package:shield/module/orders/purchase_service.dart';
import 'package:shield/module/privilege/privilege_tier.dart';
import 'package:shield/module/wallet/wallet_service.dart';

void main() {
  group('PaymentMethods.forOrder', () {
    test('offers only wallet and cash, both live', () {
      expect(PaymentMethods.forOrder, [PaymentMethods.wallet, PaymentMethods.cash]);
      expect(PaymentMethods.forOrder.every((m) => m.isLive), isTrue);
    });

    test('bank transfer and the UPI apps are untouched', () {
      expect(PaymentMethods.bankTransfer.isLive, isTrue);
      expect(PaymentMethods.googlePay.isLive, isFalse);
    });
  });

  group('FulfillmentType', () {
    test('labels read as expected', () {
      expect(FulfillmentType.homeDelivery.label, 'Home Delivery');
      expect(FulfillmentType.storePickup.label, 'Store Pickup');
    });
  });

  group('WalletService.spendBalance', () {
    setUp(() => WalletService.instance.reset());

    test('refuses to spend while the wallet is closed', () {
      expect(
        WalletService.instance.spendBalance(amount: 100, label: 'Order X'),
        isFalse,
      );
    });

    test('commission is spendable without a plan and does not consume allowance', () {
      final wallet = WalletService.instance;
      wallet.creditEarnings(amount: 500);
      expect(wallet.isActivated, isTrue);
      expect(wallet.spendBalance(amount: 100, label: 'Order X'), isTrue);
      expect(wallet.balance, 400);
      expect(wallet.redeemedThisMonth, 0);
    });
  });

  // migration: monthly-capped wallet checkout — a product purchase draws
  // only up to what this month's allowance has released, leaving any excess
  // for the member to pay another way. See checkout_screen.dart's
  // _walletShare / order.service.ts's checkout().
  group('WalletService monthly-capped checkout', () {
    setUp(() => WalletService.instance.reset());

    test('walletShareOf caps a big order at the monthly allowance, not the full balance', () {
      final wallet = WalletService.instance;
      final load = PrivilegeProgramme.loadFor(10000)!; // ₹10,000 + 10% bonus = ₹11,000
      wallet.activate(load);
      expect(wallet.isActivated, isTrue);

      // A ₹5,000 order is nowhere near the ₹11,000 balance, but this card's
      // first monthly instalment is only ~₹916 — that is what caps it.
      final share = wallet.walletShareOf(5000);
      expect(share, wallet.monthlyBalance);
      expect(share, lessThan(5000));
      expect(share, lessThan(wallet.balance));
    });

    test('walletShareOf covers a small order in full when it fits the allowance', () {
      final wallet = WalletService.instance;
      wallet.activate(PrivilegeProgramme.loadFor(10000)!);
      expect(wallet.walletShareOf(200), 200);
    });

    test('spendMonthlyShare debits the balance and shows up in redeemedThisMonth', () {
      final wallet = WalletService.instance;
      wallet.activate(PrivilegeProgramme.loadFor(10000)!);
      final balanceBefore = wallet.balance;
      final share = wallet.walletShareOf(5000);

      final spent = wallet.spendMonthlyShare(amount: share, label: 'Order SHD-1');
      expect(spent, isTrue);
      expect(wallet.balance, balanceBefore - share);
      expect(wallet.redeemedThisMonth, share);
      // The whole month's instalment was just asked for, so nothing is left.
      expect(wallet.monthlyBalance, 0);
      expect(wallet.walletShareOf(500), 0);
    });

    test('a plain spendBalance debit also counts toward redeemedThisMonth once dated this month', () {
      // Unlike the old design, redeemedThisMonth is now derived from every
      // debit dated in the current calendar month — not a separately
      // tracked counter only spendMonthlyShare moves — so it reflects real,
      // backend-hydrated spend history the same way on every platform.
      final wallet = WalletService.instance;
      wallet.activate(PrivilegeProgramme.loadFor(10000)!);
      wallet.spendBalance(amount: 300, label: 'Priced bill');
      expect(wallet.redeemedThisMonth, 300);
    });
  });

  group('OrderBill.paymentMode', () {
    Purchase prescriptionOrder({
      required int billAmount,
      required OrderPaymentStatus billStatus,
      OrderPaymentStatus paymentStatus = OrderPaymentStatus.pending,
    }) => Purchase(
      id: 'SHD-1',
      placedOn: '01 Sep 2026',
      itemCount: 1,
      mrpTotal: 0,
      paidTotal: 0,
      status: OrderStatus.processing,
      kind: OrderKind.prescription,
      paymentStatus: paymentStatus,
      billAmount: billAmount,
      billStatus: billStatus,
    );

    test('paymentMode reads "Paid" once settled, otherwise the fulfillment-driven note', () {
      final paid = prescriptionOrder(
        billAmount: 450,
        billStatus: OrderPaymentStatus.paid,
        paymentStatus: OrderPaymentStatus.paid,
      );
      expect(OrderBill(paid).paymentMode, 'Paid');

      final pendingPickup = Purchase(
        id: 'SHD-2',
        placedOn: '01 Sep 2026',
        itemCount: 1,
        mrpTotal: 100,
        paidTotal: 100,
        status: OrderStatus.processing,
        fulfillmentType: FulfillmentType.storePickup,
      );
      expect(OrderBill(pendingPickup).paymentMode, 'Pay at store');
    });

    test('Purchase.copyWith swaps only the payment fields', () {
      final order = prescriptionOrder(billAmount: 450, billStatus: OrderPaymentStatus.pending);
      final paid = order.copyWith(
        paymentStatus: OrderPaymentStatus.paid,
        billStatus: OrderPaymentStatus.paid,
      );
      expect(paid.paymentStatus, OrderPaymentStatus.paid);
      expect(paid.billStatus, OrderPaymentStatus.paid);
      expect(paid.billAmount, order.billAmount);
      expect(paid.id, order.id);
    });
  });
}
