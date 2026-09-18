import 'package:flutter/foundation.dart';

import '../../money.dart';

/// Thrown from a `CheckoutScreen.onComplete` implementation when the order
/// genuinely never made it to the backend — as opposed to this app's usual
/// best-effort repositories, which swallow a failed write and return null so
/// a flaky network never blocks the member from finishing checkout. Checkout
/// itself is the one write that can't be allowed to fail silently: showing
/// "Order placed" for an order nothing but this device ever heard of is what
/// let a member believe they'd ordered something the admin console — reading
/// the real table — never saw at all. `CheckoutScreen` catches this and
/// keeps the member on the checkout screen with [message], rather than
/// moving on to `successScreen`.
class CheckoutFailedException implements Exception {
  final String message;

  const CheckoutFailedException(this.message);

  @override
  String toString() => message;
}

/// One line of the bill a checkout is settling.
///
/// The amounts are carried as numbers rather than as pre-formatted strings so
/// that every checkout prints its bill the same way, whether the figures came
/// from a cart of medicines or from a privilege plan.
@immutable
class CheckoutLine {
  final String label;
  final double amount;

  /// A discount or a bonus — something coming off the bill rather than onto
  /// it. Printed with a minus sign and in the brand green.
  final bool isCredit;

  const CheckoutLine(this.label, this.amount, {this.isCredit = false});

  String get amountLabel =>
      '${isCredit ? '− ' : ''}₹${formatRupees(amount.round())}';
}

/// What a checkout is being asked to collect: what is being bought, what it
/// breaks down into, and how much money has to move.
///
/// Deliberately knows nothing about carts or privilege plans. Both build one
/// of these and hand it to the same checkout, which is the only reason there
/// is one payment flow in this app rather than one per thing that can be
/// bought.
@immutable
class CheckoutOrder {
  /// What is being paid for: 'Silver Shield', 'Medicine order'.
  final String title;

  /// The line under it, saying what that means in this case.
  final String subtitle;

  /// The bill, in the order it should be read. May be empty for a purchase
  /// with nothing to break down.
  final List<CheckoutLine> lines;

  /// What actually has to be transferred.
  final double amount;

  /// The short code the member quotes on the transfer so the payment can be
  /// matched to this order. Manual settlement has nothing else to match on.
  final String reference;

  /// The word on the button that finishes the whole thing off — 'Activate
  /// plan', 'Place order'. The checkout is generic; what it completes is not.
  final String submitLabel;

  /// Whether a delivery address is required before this order can be placed.
  /// True for a cart of medicines; false for a privilege plan, which is not
  /// shipped anywhere.
  final bool requiresDelivery;

  /// Whether this order is *for* a specific patient — true for a
  /// prescription or a lab booking, false for a plain product order, which
  /// only needs somewhere to send it. Only meaningful alongside
  /// [requiresDelivery]; defaults true so a caller that never set it keeps
  /// asking for one, same as before this existed.
  final bool requiresPatient;

  /// Units in the order, for the "N items" line next to the delivery
  /// estimate. Null when there is nothing to count — a privilege plan is not
  /// a quantity of anything.
  final int? itemCount;

  const CheckoutOrder({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.reference,
    required this.submitLabel,
    this.lines = const [],
    this.requiresDelivery = false,
    this.requiresPatient = true,
    this.itemCount,
  });

  String get amountLabel => '₹${formatRupees(amount.round())}';
}
