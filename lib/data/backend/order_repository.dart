import 'dart:math';

import '../../module/cart/cart_service.dart';
import '../../module/checkout/fulfillment_type.dart';
import '../../module/location/address_book.dart';
import 'address_repository.dart';
import 'backend_http.dart';

/// Reads and places standard product orders through `backend/api`'s
/// `/v1/member/{cart,orders}` routes — see `cart.service.ts`/`order.service.ts`.
///
/// Checkout here is fundamentally different in shape from the old direct-
/// Neon version: the backend has its own server-side cart, priced from live
/// product rows, and computes every total itself — a client-submitted
/// amount is never trusted. [checkoutStandardOrder] bridges the app's
/// in-memory [CartService] (still the UI's source of truth) to that
/// server-side cart at the moment of checkout: sync the lines across, then
/// check out.
///
/// Best-effort, the same contract as every repository here: an unconfigured
/// backend or the network down leaves [PurchaseService]'s in-memory record
/// as the only copy — a checkout must never fail because the backend is
/// unreachable, it just won't be visible to staff or earn anything until it
/// syncs.
class OrderRepository {
  OrderRepository._();

  // Non-const, unlike the rest of this file's siblings before this feature —
  // `_paymentMethodIdCache` below needs a mutable instance field, the same
  // reason `WalletRepository.instance` is `static final` rather than `const`.
  static final OrderRepository instance = OrderRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// `code` (`'wallet'`/`'cash'`) → the backend's numeric `payment_method.id`
  /// — resolved once against the public catalogue and cached, the same
  /// pattern `WalletRepository._tierIdCache` uses for membership tiers. The
  /// checkout DTO only accepts the numeric id; the app only knows methods by
  /// their [PaymentMethod.id] code.
  Map<String, int>? _paymentMethodIdCache;

  Future<int?> _paymentMethodIdFor(String code) async {
    final cached = _paymentMethodIdCache;
    if (cached != null) {
      return cached[code];
    }
    try {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/catalogue/payment-methods',
        auth: false,
      ) as List<dynamic>;
      final map = <String, int>{};
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final rowCode = row['code']?.toString();
        final id = row['id'];
        if (rowCode != null && id != null) {
          map[rowCode] = (id as num).toInt();
        }
      }
      _paymentMethodIdCache = map;
      return map[code];
    } catch (error) {
      BackendHttp.log('OrderRepository._paymentMethodIdFor failed', error: error);
      return null;
    }
  }

  /// Every order the member has placed, newest first — raw rows, same shape
  /// [PurchaseService] already expects from `Purchase.fromRow`.
  ///
  /// Returns `null` (not an empty list) when the backend is off or
  /// unreachable, so a transient failure is not shown as "no orders yet".
  Future<List<Map<String, dynamic>>?> listForMember() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request('GET', '/v1/member/orders')
          as List<dynamic>;
      return rows.cast<Map<String, dynamic>>();
    } catch (error) {
      BackendHttp.log('OrderRepository.listForMember failed', error: error);
      return null;
    }
  }

  /// Syncs [lines] into the backend's own cart (clearing anything stale left
  /// over from an earlier abandoned session first — a client-side cart
  /// reload must never leak into a fresh checkout), creates [address] as a
  /// fresh delivery address when given, checks out with a fresh
  /// `Idempotency-Key`, and files [receiptPayerName]/[receiptReference]/
  /// [receiptAmount]/[receiptFileName] as the manual-transfer claim against
  /// the order it just placed — matching the old `OrderReceiptInput`
  /// exactly (metadata only; the app has never uploaded the receipt photo
  /// itself anywhere).
  ///
  /// A line with no resolvable [CartLine.productId] (a stale add, or a
  /// catalogue read that never carried an id through) is skipped rather
  /// than failing the whole checkout — the same "never block the order"
  /// philosophy as every other best-effort write here.
  ///
  /// Returns the created order's id, or null when nothing was written.
  ///
  /// [fulfillmentType] and [paymentMethodCode] are migration-0031 additions:
  /// how the order reaches the member, and how it is paid for — `'wallet'`
  /// settles the order instantly (the backend debits the balance and marks
  /// it PAID in the same transaction as the order itself, see
  /// `order.service.ts`'s `checkout`), `'cash'` (or leaving this null)
  /// leaves it PENDING until it is collected in person.
  Future<int?> checkoutStandardOrder({
    required List<CartLine> lines,
    Address? address,
    String? reference,
    String? receiptPayerName,
    String? receiptReference,
    double? receiptAmount,
    String? receiptFileName,
    FulfillmentType fulfillmentType = FulfillmentType.homeDelivery,
    String? paymentMethodCode,
  }) async {
    if (!BackendHttp.isConfigured || lines.isEmpty) {
      return null;
    }
    try {
      // 1 · Clear any stale server-side lines from an earlier session.
      final existingCart = await BackendHttp.instance.request('GET', '/v1/member/cart')
          as Map<String, dynamic>;
      for (final line in (existingCart['lines'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        await BackendHttp.instance.request('DELETE', '/v1/member/cart/lines/${line['id']}');
      }

      // 2 · Add the current in-memory lines.
      for (final line in lines) {
        final productId = line.productId;
        if (productId == null) {
          BackendHttp.log(
            'OrderRepository.checkoutStandardOrder: "${line.name}" has no product id — skipped',
          );
          continue;
        }
        await BackendHttp.instance.request(
          'POST',
          '/v1/member/cart/lines',
          body: {'productId': productId, 'qty': line.qty},
        );
      }

      // 3 · A fresh delivery address, if one was chosen.
      final addressId = address == null
          ? null
          : await AddressRepository.instance.create(address);

      // 3b · The chosen payment method's numeric id, if it resolves.
      final paymentMethodId = paymentMethodCode == null
          ? null
          : await _paymentMethodIdFor(paymentMethodCode);

      // 4 · Checkout — totals are computed server-side from the lines just synced.
      final createdOrder = await BackendHttp.instance.request(
        'POST',
        '/v1/member/orders',
        body: {
          if (addressId != null) 'deliveryAddressId': addressId,
          if (reference != null) 'reference': reference,
          if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
          'fulfillmentType': fulfillmentType == FulfillmentType.storePickup
              ? 'STORE_PICKUP'
              : 'HOME_DELIVERY',
        },
        headers: {'Idempotency-Key': _newIdempotencyKey()},
      ) as Map<String, dynamic>;
      final orderId = createdOrder['id'] as int?;
      if (orderId == null) {
        return null;
      }

      // 5 · The manual-transfer claim, against the order just placed — only
      // when there is one to file. A wallet or cash order never uploads a
      // receipt (see checkout_screen.dart's `_submitDelivering`); filing an
      // empty claim for it would just be a bare row with nothing on it.
      final hasReceipt =
          receiptPayerName != null ||
          receiptReference != null ||
          receiptAmount != null ||
          (receiptFileName != null && receiptFileName.isNotEmpty);
      if (hasReceipt) {
        try {
          await BackendHttp.instance.request(
            'POST',
            '/v1/member/orders/$orderId/receipt',
            body: {
              if (receiptPayerName != null) 'payerName': receiptPayerName,
              if (receiptReference != null) 'reference': receiptReference,
              if (receiptAmount != null) 'amount': receiptAmount,
              if (receiptFileName != null) 'fileName': receiptFileName,
            },
          );
        } catch (error) {
          // The order itself is real even if the receipt claim failed to
          // attach — never unwind a placed order over this.
          BackendHttp.log('OrderRepository: receipt claim failed for order $orderId', error: error);
        }
      }

      return orderId;
    } catch (error) {
      BackendHttp.log('OrderRepository.checkoutStandardOrder failed', error: error);
      return null;
    }
  }

  /// "Pay now" on a priced-but-unpaid bill — `POST /v1/member/orders/:id/pay`
  /// (see `order.service.ts`'s `payBillWithWallet`). The backend debits the
  /// wallet for the bill's own stored amount (never a client-submitted
  /// figure) and marks the order and its bill PAID, all in one transaction.
  ///
  /// [orderId] is the backend's numeric id — [Purchase.backendId], not the
  /// order's [Purchase.id] code. Returns false, writing nothing further,
  /// when the backend is unreachable or refuses the debit (insufficient
  /// balance, or the bill is already paid).
  Future<bool> payBillWithWallet({required int orderId}) async {
    if (!BackendHttp.isConfigured) {
      return false;
    }
    try {
      await BackendHttp.instance.request(
        'POST',
        '/v1/member/orders/$orderId/pay',
        headers: {'Idempotency-Key': _newIdempotencyKey()},
      );
      return true;
    } catch (error) {
      BackendHttp.log('OrderRepository.payBillWithWallet failed', error: error);
      return false;
    }
  }

  /// A fresh random v4-shaped UUID for one checkout attempt. See
  /// `RewardsRepository`'s identical helper for why this must be
  /// high-entropy rather than derived from a timestamp.
  static String _newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int start, int end) =>
        bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
