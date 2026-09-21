import 'dart:math';

import '../../module/cart/cart_service.dart';
import '../../module/checkout/fulfillment_type.dart';
import '../../module/location/address_book.dart';
import '../../module/orders/bill_invoice.dart';
import 'address_repository.dart';
import 'backend_http.dart';
import 'care_repository.dart';

/// One order's `app.bill` row, as [OrderRepository.fetchBill] reads it back —
/// what [PurchaseService.ensureBillLoaded] needs on top of what the orders
/// list already carries ([Purchase.billAmount] / [Purchase.billStatus]): the
/// bill's picture and the itemised invoice.
class OrderBillDetail {
  /// The store's invoice picture, or null when this bill was priced but
  /// never had one attached.
  final String? image;
  final DateTime? sentAt;

  /// The itemised invoice — items, prices, store, customer, totals — or null
  /// when the backend predates it and sent only the bill row.
  final BillInvoice? invoice;

  const OrderBillDetail({
    required this.image,
    required this.sentAt,
    this.invoice,
  });
}

/// One prescription linked to an order, as [OrderRepository.fetchPrescriptions]
/// reads it back — just enough for [PrescriptionUploadedCard] to show the
/// real scan rather than a generic icon.
class OrderPrescription {
  final int id;
  final String code;

  /// The member's own uploaded scan (a `data:` URI), or null when this
  /// prescription was submitted with no photo — a script phoned in, not an
  /// error case (see `PrescriptionService.upload`'s own doc).
  final String? image;
  final String doctor;

  /// An `app.prescription_status` value — `AWAITING_REVIEW` / `READ` /
  /// `ORDERED`.
  final String status;

  const OrderPrescription({
    required this.id,
    required this.code,
    required this.image,
    required this.doctor,
    required this.status,
  });
}

/// One line item on a standard order, as [OrderRepository.fetchItems] reads
/// it back — enough for the "Items in this order" card to show the real
/// product picture rather than naming it with no picture at all.
class OrderItem {
  final String name;
  final String pack;
  final int qty;
  final int unitPrice;
  final int mrp;

  /// The product's own catalogue picture (a `data:` URI or a network URL),
  /// or null when the line carries no product (a stale cart add) or the
  /// product has since lost its picture.
  final String? image;

  const OrderItem({
    required this.name,
    required this.pack,
    required this.qty,
    required this.unitPrice,
    required this.mrp,
    required this.image,
  });
}

/// One package booked in the lab cart, as [OrderRepository.saveLabBookings]
/// sends it — the same shape root's direct-Neon `LabBookingInput` carries,
/// so `lab_cart_screen.dart`'s checkout call needs no changes beyond its
/// import to move between the two apps.
class LabBookingInput {
  final String name;
  final int testCount;
  final int profileCount;
  final String rating;
  final String booked;
  final String reportIn;
  final int unitPrice;
  final int mrp;
  final int patients;
  final String forWhom;
  final String ageRange;
  final String preparation;
  final String sample;
  final String about;

  const LabBookingInput({
    required this.name,
    this.testCount = 0,
    this.profileCount = 0,
    this.rating = '',
    this.booked = '',
    this.reportIn = '',
    required this.unitPrice,
    required this.mrp,
    required this.patients,
    this.forWhom = '',
    this.ageRange = '',
    this.preparation = '',
    this.sample = '',
    this.about = '',
  });
}

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
    /// The wallet's share of the total when [paymentMethodCode] is
    /// `'wallet'` and it does not cover the whole order — the split
    /// [WalletService.walletShareOf] worked out client-side, so the backend
    /// debits only this much (see `order.service.ts`'s `checkout`) and
    /// leaves the order PENDING with the rest due another way, instead of
    /// debiting the full total or refusing the order outright. Omitted (or
    /// null) debits the full total, same as before this existed.
    int? walletAmount,
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
          if (walletAmount != null) 'walletAmount': walletAmount,
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

  /// Places every booking in the lab cart — one `POST /v1/member/lab-bookings`
  /// call per package (see `booking.service.ts`'s `bookLabTest`). [phone] /
  /// [name] are accepted for parity with root's direct-Neon signature
  /// (`lab_cart_screen.dart`'s checkout call is shared, unchanged, between
  /// the two apps) but unused — the backend resolves identity from the
  /// session.
  ///
  /// Root's direct-Neon write upserts `app.lab_package` by slug in the same
  /// transaction, so it never needs to already know a package's id. The
  /// REST endpoint expects one instead (`labPackageId`), so this resolves
  /// each booking's real id by matching [LabBookingInput.name] against a
  /// fresh `CareRepository.fetchLabPackages()` read rather than changing
  /// what the (shared, unmodified) cart screen passes in.
  ///
  /// The backend's booking schema also wants a named `patients` array (a
  /// patient id, or a plain name) — the on-screen flow only ever collects a
  /// headcount per package (`LabCartService`/`patient_count_sheet.dart`,
  /// identical to root), so this synthesizes placeholder names
  /// ("Patient 1", "Patient 2", …) for that count instead, matching root's
  /// own booking UX exactly rather than the stricter shape the backend was
  /// also built to accept.
  ///
  /// Best-effort: a booking that fails to resolve or submit is logged and
  /// skipped rather than failing the rest of the basket.
  Future<void> saveLabBookings({
    String? phone,
    String? name,
    required List<LabBookingInput> bookings,
    Address? address,
  }) async {
    if (!BackendHttp.isConfigured || bookings.isEmpty) {
      return;
    }
    final addressId =
        address == null ? null : await AddressRepository.instance.create(address);
    final packages = await CareRepository.instance.fetchLabPackages() ?? const [];
    for (final booking in bookings) {
      final package = packages.where((p) => p.name == booking.name).firstOrNull;
      if (package == null) {
        BackendHttp.log(
          'OrderRepository.saveLabBookings: no backend package matches "${booking.name}" — skipped',
        );
        continue;
      }
      try {
        await BackendHttp.instance.request(
          'POST',
          '/v1/member/lab-bookings',
          body: {
            'labPackageId': int.parse(package.id),
            'patients': [
              for (var i = 1; i <= booking.patients; i++) {'name': 'Patient $i'},
            ],
            if (addressId != null) 'addressId': addressId,
          },
        );
      } catch (error) {
        BackendHttp.log(
          'OrderRepository.saveLabBookings failed for "${booking.name}"',
          error: error,
        );
      }
    }
  }

  /// The full `app.bill` row for one order — `GET /v1/member/orders/:id/bill`
  /// (see `order.service.ts`'s `getBillForMember`) — fetched lazily per
  /// order rather than carried on every row of `listForMember`'s list, since
  /// [OrderBillDetail.image] can be a large data URI (see [Purchase.billImage]'s
  /// own doc for why).
  ///
  /// [orderId] is the backend's numeric id ([Purchase.backendId]). Null when
  /// the backend is unreachable, or — a 404 — no bill has been sent for this
  /// order at all; either way there is nothing here for [PurchaseService.
  /// ensureBillLoaded] to apply.
  Future<OrderBillDetail?> fetchBill(int orderId) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final body =
          await BackendHttp.instance.request('GET', '/v1/member/orders/$orderId/bill')
              as Map<String, dynamic>;
      final image = (body['image'] as String?)?.trim();
      final sentAt = DateTime.tryParse((body['sentAt'] ?? '').toString());
      return OrderBillDetail(
        image: image == null || image.isEmpty ? null : image,
        sentAt: sentAt,
        invoice: invoiceFromBill(body, sentAt: sentAt),
      );
    } on BackendHttpException catch (error) {
      // 404 — "no bill sent for this order yet" — the ordinary case for
      // most orders, not a failure to log.
      if (error.isNotFound) return null;
      BackendHttp.log('OrderRepository.fetchBill failed', error: error);
      return null;
    } catch (error) {
      BackendHttp.log('OrderRepository.fetchBill failed', error: error);
      return null;
    }
  }

  /// Reads the `invoice` block `GET /v1/member/orders/:id/bill` returns beside
  /// the bill's own columns (`order.service.ts`'s `buildInvoice`) into a
  /// [BillInvoice]; null when the block is absent (an older backend).
  ///
  /// Money arrives as the `numeric` text the database uses ("70.00") and is
  /// read into exact paise. Public only so a test can feed it a response.
  static BillInvoice? invoiceFromBill(
    Map<String, dynamic> body, {
    DateTime? sentAt,
  }) {
    final raw = body['invoice'];
    if (raw is! Map<String, dynamic>) {
      return null;
    }
    String text(Map<String, dynamic>? map, String key) =>
        (map?[key] ?? '').toString().trim();
    String joined(Map<String, dynamic>? map, List<String> keys) =>
        keys.map((key) => text(map, key)).where((p) => p.isNotEmpty).join(', ');
    Map<String, dynamic>? asMap(Object? value) =>
        value is Map<String, dynamic> ? value : null;

    final customer = asMap(raw['customer']);
    final store = asMap(raw['store']);
    final address = asMap(raw['deliveryAddress']);
    final status = text(raw, 'status');

    return BillInvoice.compose(
      number: text(raw, 'number'),
      billedAt: sentAt,
      placedAt: DateTime.tryParse(text(raw, 'placedAt')),
      customerName: text(customer, 'name'),
      customerPhone: text(customer, 'phone'),
      storeName: text(store, 'name'),
      storeAddress: joined(store, ['area', 'city', 'state', 'pincode']),
      storePhone: text(store, 'phone'),
      homeDelivery: text(raw, 'fulfillmentType') != 'STORE_PICKUP',
      deliveryAddress: joined(address, [
        'house',
        'area',
        'landmark',
        'city',
        'state',
        'pincode',
      ]),
      orderStatus: status == 'DELIVERED'
          ? 'Completed'
          : status == 'CANCELLED'
          ? 'Cancelled'
          : 'In progress',
      paid:
          text(raw, 'paymentStatus') == 'PAID' ||
          text(body, 'status') == 'PAID',
      paidAt:
          DateTime.tryParse(text(body, 'paidAt')) ??
          DateTime.tryParse(text(raw, 'paidAt')),
      lines: [
        for (final line in (raw['lines'] as List<dynamic>? ?? const []))
          if (line is Map<String, dynamic>)
            InvoiceLine(
              name: text(line, 'name'),
              pack: text(line, 'pack'),
              qty: int.tryParse(text(line, 'qty')) ?? 1,
              unitPaise: paiseFrom(line['unitPrice']),
            ),
      ],
      billPaise: paiseFrom(body['amount']),
      paidTotalPaise: paiseFrom(raw['paidTotal']),
      deliveryFeePaise: paiseFrom(raw['deliveryFee']),
    );
  }

  /// The prescription(s) submitted into this order — `GET /v1/member/
  /// orders/:id/prescriptions` (see `order.service.ts`'s
  /// `getPrescriptionsForOrder`). Empty for a standard order, which never
  /// has one; null when the backend is unreachable. [orderId] is the
  /// backend's numeric id ([Purchase.backendId]).
  ///
  /// This is what [PrescriptionUploadedCard] actually shows — the member's
  /// own uploaded scan, not a generic document icon standing in for it —
  /// fetched lazily per order the same way [fetchBill] is, rather than
  /// carried on every row of [listForMember]'s list.
  Future<List<OrderPrescription>?> fetchPrescriptions(int orderId) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows =
          await BackendHttp.instance.request('GET', '/v1/member/orders/$orderId/prescriptions')
              as List<dynamic>;
      return rows.cast<Map<String, dynamic>>().map((row) {
        final image = (row['image'] as String?)?.trim();
        return OrderPrescription(
          id: (row['id'] as num).toInt(),
          code: (row['code'] ?? '').toString(),
          image: image == null || image.isEmpty ? null : image,
          doctor: (row['doctor'] ?? '').toString(),
          status: (row['status'] ?? '').toString().toUpperCase(),
        );
      }).toList(growable: false);
    } catch (error) {
      BackendHttp.log('OrderRepository.fetchPrescriptions failed', error: error);
      return null;
    }
  }

  /// This order's own line items with a real product picture against each
  /// one — `GET /v1/member/orders/:id/items` (see `OrderService.
  /// getItemsForOrder`). Empty for a prescription order, which never has
  /// `order_line` rows at all; null when the backend is unreachable.
  /// [orderId] is the backend's numeric id ([Purchase.backendId]).
  ///
  /// Fetched lazily per order, the same reasoning as [fetchBill] and
  /// [fetchPrescriptions]: a product picture is a `data:` URI that can run
  /// to a hundred KB or more, so it does not belong on every row of
  /// [listForMember]'s list.
  Future<List<OrderItem>?> fetchItems(int orderId) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request('GET', '/v1/member/orders/$orderId/items')
          as List<dynamic>;
      return rows.cast<Map<String, dynamic>>().map((row) {
        int i(Object? v) => v is int ? v : (double.tryParse((v ?? '').toString())?.round() ?? 0);
        final image = (row['image'] as String?)?.trim();
        return OrderItem(
          name: (row['name'] ?? '').toString(),
          pack: (row['pack'] ?? '').toString(),
          qty: i(row['qty']),
          unitPrice: i(row['unitPrice']),
          mrp: i(row['mrp']),
          image: image == null || image.isEmpty ? null : image,
        );
      }).toList(growable: false);
    } catch (error) {
      BackendHttp.log('OrderRepository.fetchItems failed', error: error);
      return null;
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
