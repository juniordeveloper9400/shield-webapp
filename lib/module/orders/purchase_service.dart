import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/neon/neon_http.dart';
import '../../data/neon/order_repository.dart';
import '../../dates.dart' as dates;
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_service.dart';
import '../rewards/rewards_service.dart';

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

  const Purchase({
    required this.id,
    required this.placedOn,
    required this.itemCount,
    required this.mrpTotal,
    required this.paidTotal,
    required this.status,
    this.kind = OrderKind.standard,
  });

  /// A prescription order still waiting on money: priced or not, nothing has
  /// been paid and it has not been delivered or called off.
  bool get awaitingPayment =>
      kind == OrderKind.prescription &&
      paidTotal == 0 &&
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

  /// One row of `app."order"` (see `OrderRepository.listForMember`) → a
  /// [Purchase] the earnings card and the orders list can read directly.
  factory Purchase.fromRow(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString().trim();
    int i(Object? v) => int.tryParse(str(v)) ?? 0;

    final placedOn = DateTime.tryParse(str(row['placed_on']));
    return Purchase(
      id: str(row['code']),
      placedOn: placedOn == null ? str(row['placed_on']) : dates.formatDate(placedOn),
      itemCount: i(row['item_count']),
      mrpTotal: i(row['mrp_total']),
      paidTotal: i(row['paid_total']),
      status: _statusFromDb(str(row['status'])),
      kind: _kindFromDb(str(row['kind'])),
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
/// Backed by `app."order"` (see `OrderRepository.listForMember`), keyed to
/// the signed-in mobile number the same way [RewardsService] is: [attach]
/// wires it to the auth session, loading on sign-in and clearing on sign-out,
/// so what a member sees here is their own real order history rather than a
/// fixture every fresh install showed alike.
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

  Future<void> _load() async {
    final phone = _phone;
    if (phone == null) {
      _status = PurchaseStatus.idle;
      _inFlight = null;
      notifyListeners();
      return;
    }
    if (!NeonHttp.isConfigured) {
      _status = PurchaseStatus.error;
      _inFlight = null;
      notifyListeners();
      return;
    }
    _status = PurchaseStatus.loading;
    notifyListeners();
    try {
      final rows = await OrderRepository.instance.listForMember(phone);
      if (rows != null) {
        _purchases
          ..clear()
          ..addAll(rows.map(Purchase.fromRow));
        _status = PurchaseStatus.ready;
      } else {
        _status = PurchaseStatus.error;
      }
    } catch (error) {
      NeonHttp.log('PurchaseService load failed', error: error);
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
  }) {
    final purchase = Purchase(
      id: id,
      placedOn: placedOn,
      itemCount: itemCount,
      mrpTotal: mrpTotal,
      paidTotal: paidTotal,
      status: status,
      kind: kind,
    );
    _purchases.insert(0, purchase);
    notifyListeners();

    // Reward points for what was actually paid (₹100 → 10 pts). Best-effort
    // and signed-in only; a prescription order still awaiting pricing has
    // paidTotal 0 and earns nothing until it is paid.
    if (purchase.status.counts && paidTotal > 0) {
      unawaited(
        RewardsService.instance.awardForOrder(code: id, paidRupees: paidTotal),
      );
    }

    return purchase;
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
