import '../../money.dart';
import '../../module/home/product_showcase.dart';
import 'backend_http.dart';

/// Reads the storefront catalogue from `backend/api`'s public catalogue
/// routes — `GET /v1/public/catalogue/products` (paginated, so this walks
/// every page), joined client-side against `GET .../categories` and
/// `GET .../categories/:id/subcategories` for the display names the raw
/// product row doesn't carry.
///
/// Read-only. Products are created and maintained from the pharmacy admin
/// console (`shieldweb`), never from the app; this repository only lists
/// what is on the shelf.
///
/// Best-effort, like the other backend repositories here: with an
/// unconfigured backend (tests, a build with no
/// `BACKEND_API_BASE_URL`) or the network down, [listActive] returns `null`
/// so the caller can tell "the catalogue could not be loaded" from "the
/// catalogue is empty".
class ProductRepository {
  const ProductRepository._();

  static const ProductRepository instance = ProductRepository._();

  /// Whether a read would actually reach the backend.
  bool get isAvailable => BackendHttp.isConfigured;

  /// Every `ACTIVE` product, newest-first per the backend's own ordering,
  /// mapped to the UI [Product] model.
  ///
  /// Returns `null` (not an empty list) when the backend is off or
  /// unreachable, so a transient failure is not shown as an empty shop.
  Future<List<Product>?> listActive() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final categories = await _fetchCategories();
      final subcategoryLabels = await _fetchSubcategoryLabels(categories.keys);
      final rows = await _fetchAllProductPages();
      return rows
          .map((row) => _toProduct(row, categories, subcategoryLabels))
          .where((product) => product.name.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      BackendHttp.log('ProductRepository.listActive failed', error: error);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllProductPages() async {
    final all = <Map<String, dynamic>>[];
    int? cursor;
    while (true) {
      final path = cursor == null
          ? '/v1/public/catalogue/products?limit=100'
          : '/v1/public/catalogue/products?limit=100&cursor=$cursor';
      final page = await BackendHttp.instance.request('GET', path, auth: false)
          as Map<String, dynamic>;
      all.addAll((page['items'] as List<dynamic>).cast<Map<String, dynamic>>());
      final next = page['nextCursor'];
      if (next == null) {
        break;
      }
      cursor = next is int ? next : int.tryParse(next.toString());
      if (cursor == null) {
        break;
      }
    }
    return all;
  }

  /// `{categoryId: (slug, title)}`.
  Future<Map<int, (String, String)>> _fetchCategories() async {
    final rows = await BackendHttp.instance.request(
      'GET',
      '/v1/public/catalogue/categories',
      auth: false,
    ) as List<dynamic>;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        (row['id'] as num).toInt(): (
          (row['slug'] ?? '').toString(),
          (row['title'] ?? '').toString(),
        ),
    };
  }

  /// `{subcategoryId: label}`, across every category — the backend only
  /// exposes subcategories one category at a time.
  Future<Map<int, String>> _fetchSubcategoryLabels(Iterable<int> categoryIds) async {
    final labels = <int, String>{};
    for (final categoryId in categoryIds) {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/catalogue/categories/$categoryId/subcategories',
        auth: false,
      ) as List<dynamic>;
      for (final row in rows.cast<Map<String, dynamic>>()) {
        labels[(row['id'] as num).toInt()] = (row['label'] ?? '').toString();
      }
    }
    return labels;
  }

  static Product _toProduct(
    Map<String, dynamic> row,
    Map<int, (String, String)> categories,
    Map<int, String> subcategoryLabels,
  ) {
    String str(Object? v) => (v ?? '').toString().trim();
    double dec(Object? v) => double.tryParse(str(v)) ?? 0;
    String? orNull(String v) => v.isEmpty ? null : v;

    final price = dec(row['price']);
    final rawMrp = dec(row['mrp']);
    final mrp = rawMrp <= 0 ? price : rawMrp;

    final categoryId = row['categoryId'];
    final category = categoryId == null ? null : categories[(categoryId as num).toInt()];
    final slug = category?.$1 ?? '';
    final categoryTitle = category?.$2 ?? '';

    final subcategoryId = row['subcategoryId'];
    final subcategoryLabel = subcategoryId == null
        ? ''
        : subcategoryLabels[(subcategoryId as num).toInt()] ?? '';

    var discount = str(row['discountLabel']);
    if (discount.isEmpty && mrp > price && price > 0) {
      discount = '${(((mrp - price) / mrp) * 100).round()}% OFF';
    }

    return Product(
      id: orNull(str(row['uuid'])),
      backendId: (row['id'] as num?)?.toInt(),
      name: str(row['name']),
      pack: str(row['pack']),
      brand: orNull(str(row['brand'])),
      categorySlug: orNull(slug),
      categoryTitle: orNull(categoryTitle),
      subcategoryLabel: orNull(subcategoryLabel),
      price: formatRupees(price.round()),
      mrp: formatRupees(mrp.round()),
      discountLabel: orNull(discount),
      icon: iconForCategorySlug(slug),
      image: orNull(str(row['image'])),
      prescriptionOnly: row['isPrescriptionOnly'] == true,
      outOfStock: dec(row['stockQuantity']) <= 0,
      isPopular: row['isPopular'] == true,
      isDeal: row['isDeal'] == true,
      isOfferOfDay: row['isOfferOfDay'] == true,
    );
  }
}
