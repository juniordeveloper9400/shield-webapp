import 'package:flutter/foundation.dart';

import 'fulfillment_type.dart';
import 'payment_method.dart';
import 'shield_payee.dart';

/// Proof that a member says they have paid.
///
/// A claim, not a confirmation. Nothing in this app can see a bank account,
/// so what comes back from a checkout is what the member handed over — the
/// method, the picture of the transfer, and the reference if they had one —
/// and it is settled by a person at the other end. Screens that act on one of
/// these should say "received", never "paid".
@immutable
class PaymentReceipt {
  final PaymentMethod method;

  /// The receipt image, as it was named on the device.
  final String fileName;
  final int bytes;

  /// The receipt image itself, `data:image/jpeg;base64,…`, so the review
  /// console shows the picture and not just [fileName]. Null when the picker
  /// could not read the bytes (or in tests).
  final String? imageDataUrl;

  /// The bank's own reference for the transfer — a UTR or a transaction ID.
  /// Mandatory: it is what the checkout collects so a person settling the
  /// claim can match this picture to a line on the statement.
  final String bankReference;

  /// The code the order was quoted under, carried through so a submission can
  /// be matched back to what it was paying for.
  final String orderReference;

  /// The store/admin the money was sent to.
  final String storeId;

  /// The bank account selected for that store.
  final StoreBankAccount bankAccount;

  /// The field staff or agent code attached to this payment.
  final String agentCode;

  final DateTime submittedAt;

  /// How a delivering order reaches the member: shipped, or held for
  /// pickup. Defaults to home delivery so the Health-Pass path — which never
  /// sets this — keeps its existing meaning.
  final FulfillmentType fulfillmentType;

  /// Whether [method] settled this order instantly off the SHIELD wallet,
  /// rather than being a claim someone still has to collect on or settle
  /// manually. False for every existing caller — a bank-transfer receipt is
  /// never paid by wallet.
  final bool paidViaWallet;

  const PaymentReceipt({
    required this.method,
    required this.fileName,
    required this.bytes,
    required this.orderReference,
    required this.storeId,
    required this.bankAccount,
    required this.agentCode,
    required this.submittedAt,
    required this.bankReference,
    this.imageDataUrl,
    this.fulfillmentType = FulfillmentType.homeDelivery,
    this.paidViaWallet = false,
  });
}
