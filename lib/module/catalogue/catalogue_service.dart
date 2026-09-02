import 'package:flutter/foundation.dart';

import '../../data/neon/neon_http.dart';
import '../../data/neon/product_repository.dart';
import '../home/product_showcase.dart';

/// Where the catalogue load has got to.
enum CatalogueStatus {
  /// Not asked for yet.
  idle,

  /// A load is in flight.
  loading,

  /// Loaded, with at least one product.
  ready,

  /// Loaded, but the pharmacy has not added any products yet.
  empty,

  /// The database is off, unreachable, or returned an error.
  error,
}

/// The customer app's single view of the storefront catalogue.
///
/// Loads every `ACTIVE` product from Neon once per session (see
/// [ProductRepository]) and keeps it in memory. The home rows, the category
/// listings, search and the product-detail "also bought" rail all read from
/// here, so whatever a pharmacy admin adds in the console shows up everywhere
/// in the app at once.
///
/// This is a single-session web app and the catalogue is small and changes
/// rarely within a visit, so there is one load plus a manual [refresh] — no
/// polling.
class CatalogueService extends ChangeNotifier {
  CatalogueService._();

  static final CatalogueService instance = CatalogueService._();

  CatalogueStatus _status = CatalogueStatus.idle;
  CatalogueStatus get status => _status;

  List<Product> _all = const [];

  /// Every active product, newest first.
  List<Product> get all => _all;

  /// Whether a load would actually reach the database.
  bool get isConfigured => NeonHttp.isConfigured;

  bool get isLoading => _status == CatalogueStatus.loading;
  bool get hasProducts => _all.isNotEmpty;

  /// True once a load has finished — successfully or not — so a screen can tell
  /// "still loading" from "loaded and there is simply nothing here".
  bool get isSettled =>
      _status == CatalogueStatus.ready ||
      _status == CatalogueStatus.empty ||
      _status == CatalogueStatus.error;

  Future<void>? _inFlight;

  /// Loads the catalogue the first time it is needed. Safe to call from every
  /// screen's `initState`: concurrent calls share one request and a finished
  /// load is a no-op. Call [refresh] to force a reload.
  Future<void> ensureLoaded() {
    if (isSettled) {
      return Future.value();
    }
    return _inFlight ??= _load();
  }

  /// Drop what was loaded and fetch again.
  Future<void> refresh() {
    _inFlight = null;
    _status = CatalogueStatus.idle;
    return ensureLoaded();
  }

  Future<void> _load() async {
    if (!NeonHttp.isConfigured) {
      _set(CatalogueStatus.error, const []);
      _inFlight = null;
      return;
    }
    _set(CatalogueStatus.loading, _all);
    try {
      final products = await ProductRepository.instance.listActive();
      if (products == null) {
        _set(CatalogueStatus.error, const []);
      } else {
        _set(
          products.isEmpty ? CatalogueStatus.empty : CatalogueStatus.ready,
          products,
        );
      }
    } catch (error) {
      NeonHttp.log('CatalogueService load failed', error: error);
      _set(CatalogueStatus.error, const []);
    } finally {
      _inFlight = null;
    }
  }

  void _set(CatalogueStatus status, List<Product> products) {
    _status = status;
    _all = products;
    notifyListeners();
  }

  // ---- derived views ------------------------------------------------------

  /// How many products a home row shows before "View all".
  static const int rowLimit = 12;

  /// Most recently added — the row keeps its "Popular Items" title but the
  /// catalogue has no popularity signal, so newest is the honest proxy.
  List<Product> get popularPicks => _all.take(rowLimit).toList();

  /// Products with a discount, steepest first.
  List<Product> get dealsYouLove {
    final withDeal = _all.where((p) => _discountPercent(p) > 0).toList()
      ..sort((a, b) => _discountPercent(b).compareTo(_discountPercent(a)));
    return withDeal.take(rowLimit).toList();
  }

  /// The "Vitamins & Supplements" storefront category.
  List<Product> get wellness =>
      byCategorySlug('vitamins-supplements').take(rowLimit).toList();

  /// Products filed under a category slug (`personal-care`, `diabetes-care`, …).
  List<Product> byCategorySlug(String slug) =>
      _all.where((p) => p.categorySlug == slug).toList(growable: false);

  /// Products filed under a category by its display title, matched
  /// case-insensitively — the bridge the category screens use, since they key
  /// off [CategoryCatalogue]'s titles.
  List<Product> byCategoryTitle(String title) {
    final needle = title.trim().toLowerCase();
    return _all
        .where((p) => (p.categoryTitle ?? '').trim().toLowerCase() == needle)
        .toList(growable: false);
  }

  /// Name / brand / pack substring match. Empty for a blank query.
  List<Product> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const [];
    }
    return _all
        .where((p) =>
            p.name.toLowerCase().contains(needle) ||
            (p.brand ?? '').toLowerCase().contains(needle) ||
            p.pack.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  static int _discountPercent(Product p) {
    final label = p.discountLabel;
    if (label == null) {
      return 0;
    }
    return int.tryParse(label.split('%').first.trim()) ?? 0;
  }
}
