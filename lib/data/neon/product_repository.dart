import '../../module/home/product_showcase.dart';
import 'neon_http.dart';

/// Reads the storefront catalogue — `app.product`, joined to
/// `app.product_category` — from Neon over the HTTP SQL endpoint (see
/// [NeonHttp]).
///
/// Read-only. Products are created and maintained from the pharmacy admin
/// console (`shieldweb`), never from the app; this repository only lists what
/// is on the shelf.
///
/// Best-effort, like the other Neon repositories: with no `DATABASE_URL`
/// compiled in (tests, or a web build that was not given the define) or the
/// network down, [listActive] returns `null` so the caller can tell "the
/// catalogue could not be loaded" from "the catalogue is empty".
class ProductRepository {
  const ProductRepository._();

  static const ProductRepository instance = ProductRepository._();

  /// Whether a read would actually reach the database.
  bool get isAvailable => NeonHttp.isConfigured;

  /// Every `ACTIVE` product, newest first, mapped to the UI [Product] model.
  ///
  /// Returns `null` (not an empty list) when the database is off or
  /// unreachable, so a transient failure is not shown as an empty shop.
  Future<List<Product>?> listActive() async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await NeonHttp.instance.query(r'''
        SELECT p.uuid,
               p.name,
               p.pack,
               p.brand,
               c.slug  AS category_slug,
               c.title AS category_title,
               s.label AS subcategory_label,
               p.price,
               p.mrp,
               p.discount_label,
               p.is_prescription_only,
               p.stock_quantity,
               p.image,
               p.is_popular,
               p.is_deal,
               p.is_offer_of_day
        FROM app.product p
        LEFT JOIN app.product_category    c ON c.id = p.category_id
        LEFT JOIN app.product_subcategory s ON s.id = p.subcategory_id
        WHERE upper(p.status) = 'ACTIVE'
        ORDER BY p.created_at DESC, p.name
      ''');
      return rows
          .map(Product.fromRow)
          .where((product) => product.name.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      NeonHttp.log('ProductRepository.listActive failed', error: error);
      return null;
    }
  }
}
