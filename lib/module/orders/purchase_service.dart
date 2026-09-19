import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend/backend_http.dart';
import '../../data/backend/order_repository.dart';
import '../../dates.dart' as dates;
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_service.dart';
import '../checkout/fulfillment_type.dart';

enum PurchaseStatus { idle, loading, ready, error }

/// Where an order has got to.
enum OrderStatus {
  delivered('Delivered', AppColors.greenTint, AppColors.brandGreenDark),
  outForDelivery('Out for delivery', AppColors.offerTint, AppColors.brandBlue),
  processing('Processing', Color(0xFFFDF3E0), Color(0xFFB4761A)),
  cancelled('Cancelled', Color(0xFFFBEBEB), Color(0xFFB4322F));

  final String label;
  final Color background;
  final Color foreground;

  const OrderStatus(this.label, this.background, this.foreground);

  /// Whether this order still counts. A cancelled order was never paid for,
  /// so it saved nothing and must not be added into what a member has earned.
  bool get counts => this != OrderStatus.cancelled;
}

/// Where an order came from — which decides the stages it moves through.
///
/// A [standard] order is picked from stock and goes straight to packing. A
/// [prescription] order is read and priced by a pharmacist first, so its
/// tracker carries two stages the standard one does not.
enum OrderKind { standard, prescription }

/// Whether an order (or the bill on a prescription order) has actually been
/// paid — the `paymentStatus`/`billStatus` token `GET /v1/member/orders`
/// hands back on each row, read back the same way on both.
enum OrderPaymentStatus { pending, paid }

/// One completed purchase: what it was worth at list price, and what was
/// actually paid for it.
///
/// Both figures are kept rather than a discount percentage, because the
/// saving is the difference between two real amounts. A rate would have to be
/// applied to something to become money again, and every application is
/// another chance for the figure on one screen to disagree with the figure on
/// another.
@immutable
class Purchase {
  final String id;
  final String placedOn;
  final int itemCount;

  /// What the items on this order add up to at their printed price.
  final int mrpTotal;

  /// What the member actually paid.
  final int paidTotal;

  final OrderStatus status;

  /// What kind of order this is. Defaults to [OrderKind.standard] so every
  /// existing call site and stored line keeps its meaning.
  final OrderKind kind;

  /// The backend's own numeric `order.id` — an opaque pass-through
  /// identifier carried alongside [id] (the order's `code`, which is what
  /// every screen displays and matches on) so a "Pay now" can address
  /// `POST /v1/member/orders/:id/pay`, which the backend addresses by
  /// numeric id rather than code. Null for an order not yet synced from
  /// `GET /v1/member/orders` — see [Purchase.fromRow].
  final int? backendId;

  /// How this order reaches the member. Defaults to
  /// [FulfillmentType.homeDelivery] so every existing call site and stored
  /// line keeps its meaning.
  final FulfillmentType fulfillmentType;

  /// Whether this order itself has been paid — distinct from [billStatus],
  /// which is what a prescription's priced bill carries. A standard order
  /// paid by wallet at checkout is [OrderPaymentStatus.paid] the moment it is
  /// placed; a cash order stays [OrderPaymentStatus.pending] until someone at
  /// the counter or on the delivery round collects it.
  final OrderPaymentStatus paymentStatus;

  /// What the pharmacist priced this prescription's bill at, in whole
  /// rupees. Null until `app.bill` has been priced.
  final int? billAmount;

  /// Whether [billAmount] has actually been paid. Null until the bill has a
  /// price at all.
  final OrderPaymentStatus? billStatus;

  /// The store's own manually-attached invoice picture — `GET /v1/member/
  /// orders/:id/bill`'s `image` (see `OrderRepository.fetchBill`), not
  /// something `GET /v1/member/orders` carries on the list row itself (an
  /// invoice photo can be a large data URI; the list stays cheap and this
  /// is fetched lazily, once, when an order with [billStatus] set is
  /// actually opened — see `PurchaseService.ensureBillLoaded`). Null until
  /// that fetch has landed, same as on a fresh order with no bill sent yet.
  final String? billImage;

  /// When the store sent [billImage] — `GET /v1/member/orders/:id/bill`'s
  /// `sentAt`. Null until fetched, same as [billImage].
  final DateTime? billedAt;

  const Purchase({
    required this.id,
    required this.placedOn,
    required this.itemCount,
    required this.mrpTotal,
    required this.paidTotal,
    required this.status,
    this.kind = OrderKind.standard,
    this.backendId,
    this.fulfillmentType = FulfillmentType.homeDelivery,
    this.paymentStatus = OrderPaymentStatus.pending,
    this.billAmount,
    this.billStatus,
    this.billImage,
    this.billedAt,
  });

  /// A copy with just the payment fields swapped in — what a wallet "Pay now"
  /// applies once the debit has gone through, so the order and its bill read
  /// as paid without waiting on the next full server sync. [billImage] /
  /// [billedAt] are for `ensureBillLoaded`'s own lazy-fetch merge instead —
  /// kept as separate parameters from the payment ones above rather than
  /// folded into one bigger "any field" copyWith, since the two callers
  /// never need to set both at once.
  Purchase copyWith({
    OrderPaymentStatus? paymentStatus,
    OrderPaymentStatus? billStatus,
    String? billImage,
    DateTime? billedAt,
  }) => Purchase(
    id: id,
    placedOn: placedOn,
    itemCount: itemCount,
    mrpTotal: mrpTotal,
    paidTotal: paidTotal,
    status: status,
    kind: kind,
    backendId: backendId,
    fulfillmentType: fulfillmentType,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    billAmount: billAmount,
    billStatus: billStatus ?? this.billStatus,
    billImage: billImage ?? this.billImage,
    billedAt: billedAt ?? this.billedAt,
  );

  /// Whether the store has actually sent an invoice picture for this order —
  /// gates [StoreInvoiceCard], the same way the root SHIELD app's identical
  /// getter on its own (direct-Neon) `Purchase` does.
  bool get hasBill => billImage != null;

  /// An order still waiting on money: priced or not, standard or
  /// prescription, the backend has not marked it paid, and it has not been
  /// delivered or called off. Every order settles the same way now — a call
  /// from the store and an OTP read back on delivery, never an in-app "Pay
  /// now" — so the tracker's callout reads the same for both kinds.
  bool get awaitingPayment =>
      paymentStatus != OrderPaymentStatus.paid &&
      status != OrderStatus.delivered &&
      status != OrderStatus.cancelled;

  /// What the order earned: the gap between the printed price and the bill.
  ///
  /// A ₹500 product bought for ₹450 earned ₹50. Never negative — an order
  /// that somehow cost more than list price did not earn a negative amount,
  /// it earned nothing.
  int get saved => mrpTotal - paidTotal < 0 ? 0 : mrpTotal - paidTotal;

  String get paidLabel => '₹${formatRupees(paidTotal)}';

  String get mrpLabel => '₹${formatRupees(mrpTotal)}';

  String get savedLabel => '₹${formatRupees(saved)}';

  /// One row of `GET /v1/member/orders` (see `OrderRepository.listForMember`)
  /// → a [Purchase] the earnings card and the orders list can read directly.
  /// Money fields come back as decimal strings (Postgres `numeric` via
  /// Drizzle), parsed the same defensive way the old Neon rows were.
  factory Purchase.fromRow(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString().trim();
    int i(Object? v) => v is int ? v : (double.tryParse(str(v))?.round() ?? 0);
    int? iOrNull(Object? v) => v == null ? null : i(v);

    final placedOn = DateTime.tryParse(str(row['placedOn']));
    final billAmount = row['billAmount'] == null ? null : i(row['billAmount']);
    return Purchase(
      id: str(row['code']),
      placedOn: placedOn == null ? str(row['placedOn']) : dates.formatDateTime12h(placedOn),
      itemCount: i(row['itemCount']),
      mrpTotal: i(row['mrpTotal']),
      paidTotal: i(row['paidTotal']),
      status: _statusFromDb(str(row['status'])),
      kind: _kindFromDb(str(row['kind'])),
      backendId: iOrNull(row['id']),
      fulfillmentType: str(row['fulfillmentType']).toUpperCase() == 'STORE_PICKUP'
          ? FulfillmentType.storePickup
          : FulfillmentType.homeDelivery,
      paymentStatus: str(row['paymentStatus']).toUpperCase() == 'PAID'
          ? OrderPaymentStatus.paid
          : OrderPaymentStatus.pending,
      billAmount: billAmount,
      billStatus: row['billStatus'] == null
          ? null
          : (str(row['billStatus']).toUpperCase() == 'PAID'
                ? OrderPaymentStatus.paid
                : OrderPaymentStatus.pending),
    );
  }
}

OrderStatus _statusFromDb(String token) {
  switch (token.toUpperCase()) {
    case 'DELIVERED':
      return OrderStatus.delivered;
    case 'OUT_FOR_DELIVERY':
      return OrderStatus.outForDelivery;
    case 'CANCELLED':
      return OrderStatus.cancelled;
    case 'PROCESSING':
    default:
      return OrderStatus.processing;
  }
}

OrderKind _kindFromDb(String token) =>
    token.toUpperCase() == 'PRESCRIPTION' ? OrderKind.prescription : OrderKind.standard;

/// The order book, and the earnings that come out of it.
///
/// One place, because the orders list and the earnings card were otherwise
/// two fixtures of the same purchases: a screen that lists four orders and a
/// card that totals a different four is the app disagreeing with itself over
/// money. The list reads [purchases]; the card reads the sums below it.
///
/// Backed by `app."order"` (see `OrderRepository.listForMember`), following
/// the auth session the same way `RewardsService` does: [attach] wires it
/// to the session, loading on sign-in and clearing on sign-out, so what a
/// member sees here is their own real order history rather than a fixture
/// every fresh install showed alike.
class PurchaseService extends ChangeNotifier {
  PurchaseService._();

  static final PurchaseService instance = PurchaseService._();

  final List<Purchase> _purchases = [];

  List<Purchase> get purchases => List.unmodifiable(_purchases);

  bool get isEmpty => _purchases.isEmpty;

  PurchaseStatus _status = PurchaseStatus.idle;
  PurchaseStatus get status => _status;
  bool get isLoading => _status == PurchaseStatus.loading;

  String? _phone;
  bool _attached = false;
  Future<void>? _inFlight;

  /// Follows the auth session: (re)loads on sign-in, clears on sign-out. Safe
  /// to call more than once. Call from `main()`, alongside the other services
  /// that key their data to the signed-in member.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    AuthService.instance.currentUser.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final phone = AuthService.instance.currentUser.value?.phone;
    if (phone == _phone) {
      return;
    }
    _phone = phone;
    if (phone == null) {
      _purchases.clear();
      _status = PurchaseStatus.idle;
      _inFlight = null;
      notifyListeners();
    } else {
      unawaited(refresh());
    }
  }

  /// Loads the member's orders if not already loaded. A no-op while signed
  /// out.
  Future<void> ensureLoaded() {
    if (_phone == null || _status == PurchaseStatus.ready) {
      return Future.value();
    }
    return _inFlight ??= _load();
  }

  /// Re-reads the order book now (after a checkout, or pull-to-refresh).
  Future<void> refresh() {
    _inFlight = null;
    return _inFlight ??= _load();
  }

  /// Fetches [order]'s bill detail — the store's invoice picture, in
  /// particular, which the orders list never carries (see [Purchase.billImage]'s
  /// own doc) — and merges it into the matching entry in [purchases]. Call
  /// once when an order's detail screen opens; a no-op when there is
  /// nothing to fetch ([order.billStatus] null — the list join found no
  /// `app.bill` row at all for this order) or [Purchase.billImage] is
  /// already set from an earlier call.
  Future<void> ensureBillLoaded(Purchase order) async {
    if (order.billStatus == null || order.billImage != null) {
      return;
    }
    final backendId = order.backendId;
    if (backendId == null) {
      return;
    }
    final bill = await OrderRepository.instance.fetchBill(backendId);
    if (bill == null) {
      return;
    }
    final index = _purchases.indexWhere((p) => p.id == order.id);
    if (index < 0) {
      return;
    }
    _purchases[index] = _purchases[index].copyWith(
      billImage: bill.image,
      billedAt: bill.sentAt,
    );
    notifyListeners();
  }

  Future<void> _load() async {
    final phone = _phone;
    if (phone == null) {
      _status = PurchaseStatus.idle;
      _inFlight = null;
      notifyListeners();
      return;
    }
    if (!BackendHttp.isConfigured) {
      _status = PurchaseStatus.error;
      _inFlight = null;
      notifyListeners();
      return;
    }
    _status = PurchaseStatus.loading;
    notifyListeners();
    try {
      final rows = await OrderRepository.instance.listForMember();
      if (rows != null) {
        _purchases
          ..clear()
          ..addAll(rows.map(Purchase.fromRow));
        _status = PurchaseStatus.ready;
      } else {
        _status = PurchaseStatus.error;
      }
    } catch (error) {
      BackendHttp.log('PurchaseService load failed', error: error);
      _status = PurchaseStatus.error;
    } finally {
      _inFlight = null;
      notifyListeners();
    }
  }

  /// Orders that still count — everything but the cancelled ones.
  Iterable<Purchase> get _counted =>
      _purchases.where((purchase) => purchase.status.counts);

  /// Orders still on their way: what the dashboard calls active.
  int get activeCount => _purchases
      .where(
        (purchase) =>
            purchase.status == OrderStatus.processing ||
            purchase.status == OrderStatus.outForDelivery,
      )
      .length;

  /// What everything bought would have cost at printed prices.
  int get mrpTotal =>
      _counted.fold(0, (sum, purchase) => sum + purchase.mrpTotal);

  /// What was actually paid for it.
  int get paidTotal =>
      _counted.fold(0, (sum, purchase) => sum + purchase.paidTotal);

  /// The whole of what buying through SHIELD has earned.
  ///
  /// Added up from the orders rather than stored, so it cannot fall behind
  /// the list it is a sum of.
  int get savedTotal => _counted.fold(0, (sum, purchase) => sum + purchase.saved);

  String get mrpLabel => '₹${formatRupees(mrpTotal)}';

  String get paidLabel => '₹${formatRupees(paidTotal)}';

  String get savedLabel => '₹${formatRupees(savedTotal)}';

  /// The share of list price the member has kept, 0..1.
  ///
  /// Worked out at the end, over the totals, rather than averaged across the
  /// orders' own rates — a 40% saving on ₹100 and a 5% saving on ₹5,000 do not
  /// average to 22.5% of anything a member spent.
  double get savedFraction => mrpTotal <= 0 ? 0 : savedTotal / mrpTotal;

  /// "26%" — the same fraction as a whole number of percent.
  String get savedPercentLabel => '${(savedFraction * 100).round()}%';

  /// Files a completed order and returns the record that was filed, so a
  /// confirmation screen can carry the member straight to it.
  Purchase record({
    required String id,
    required String placedOn,
    required int itemCount,
    required int mrpTotal,
    required int paidTotal,
    OrderStatus status = OrderStatus.processing,
    OrderKind kind = OrderKind.standard,
    FulfillmentType fulfillmentType = FulfillmentType.homeDelivery,
    OrderPaymentStatus paymentStatus = OrderPaymentStatus.pending,
  }) {
    final purchase = Purchase(
      id: id,
      placedOn: placedOn,
      itemCount: itemCount,
      mrpTotal: mrpTotal,
      paidTotal: paidTotal,
      status: status,
      kind: kind,
      fulfillmentType: fulfillmentType,
      paymentStatus: paymentStatus,
    );
    _purchases.insert(0, purchase);
    notifyListeners();

    // Reward points for what was actually paid, and advancing the buyer's
    // own inbound referral to TRANSACTED, both now happen automatically on
    // the backend inside the checkout transaction itself
    // (`order.service.ts`'s `checkout`) — nothing to trigger client-side any
    // more for a standard order. A prescription order's `paidTotal` is
    // always 0 (priced at the counter later), so it was never eligible for
    // either anyway.

    return purchase;
  }

  /// Replaces one order in place — what a wallet "Pay now" calls once its
  /// debit has gone through, so the screen it was tapped from reflects the
  /// payment without waiting on the next [refresh]. A no-op when [updated]
  /// is not (by id) an order already on file.
  void updateOne(Purchase updated) {
    final index = _purchases.indexWhere((p) => p.id == updated.id);
    if (index == -1) {
      return;
    }
    _purchases[index] = updated;
    notifyListeners();
  }

  /// Drops [id]'s optimistic local copy — called when the real backend
  /// checkout behind a [record] call turns out to have failed. Without
  /// this, an order that was never actually written to `app."order"` would
  /// still sit in "My Orders" claiming to be placed, with nothing for the
  /// admin console (which reads the real table) to ever show for it. A
  /// no-op when [id] isn't (any longer) on file.
  void discard(String id) {
    final before = _purchases.length;
    _purchases.removeWhere((p) => p.id == id);
    if (_purchases.length != before) {
      notifyListeners();
    }
  }

  @visibleForTesting
  void reset() {
    _purchases.clear();
    seedSampleOrders();
    notifyListeners();
  }

  @visibleForTesting
  void clear() {
    _purchases.clear();
    notifyListeners();
  }

  /// The order history a fresh install is shown, newest first.
  ///
  /// Every line carries both prices, so the earnings card has something real
  /// to subtract rather than a percentage applied to a total.
  void seedSampleOrders() {
    if (_purchases.isNotEmpty) {
      return;
    }
    _purchases.addAll(const [
      Purchase(
        id: 'SHD-100482',
        placedOn: '16 Aug 2026',
        itemCount: 4,
        mrpTotal: 1686,
        paidTotal: 1248,
        status: OrderStatus.delivered,
      ),
      Purchase(
        id: 'SHD-100461',
        placedOn: '12 Aug 2026',
        itemCount: 2,
        mrpTotal: 800,
        paidTotal: 640,
        status: OrderStatus.outForDelivery,
      ),
      // Filled from an uploaded prescription, so its tracker runs the longer
      // pharmacist route. Already priced and paid, so it reads like any other
      // order in the list.
      Purchase(
        id: 'SHD-100433',
        placedOn: '04 Aug 2026',
        itemCount: 7,
        mrpTotal: 2820,
        paidTotal: 2115,
        status: OrderStatus.processing,
        kind: OrderKind.prescription,
      ),
      // Cancelled, so it is listed but earns nothing.
      Purchase(
        id: 'SHD-100398',
        placedOn: '27 Jul 2026',
        itemCount: 1,
        mrpTotal: 361,
        paidTotal: 289,
        status: OrderStatus.cancelled,
      ),
    ]);
  }
}
