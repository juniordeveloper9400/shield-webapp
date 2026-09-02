import '../catalogue/catalogue_service.dart';
import '../home/product_showcase.dart';

/// Product search, served straight from the live catalogue
/// ([CatalogueService]) rather than a flattened copy of hand-written lists.
class SearchCatalogue {
  const SearchCatalogue._();

  /// The full pool a search runs against — every active product.
  static List<Product> get all => CatalogueService.instance.all;

  /// Products whose name, brand or pack contains [query]. Empty for a blank
  /// query — a box that has not been typed into has not asked for anything.
  static List<Product> search(String query) =>
      CatalogueService.instance.search(query);

  /// A few searches offered before anything is typed: the catalogue's own
  /// brands when it has loaded, otherwise some generic starting points.
  static List<String> get suggestions {
    final brands = <String>{
      for (final product in CatalogueService.instance.all)
        if ((product.brand ?? '').trim().isNotEmpty) product.brand!.trim(),
    }.take(8).toList();
    if (brands.isNotEmpty) {
      return brands;
    }
    return const [
      'Tablet',
      'Syrup',
      'Vitamin',
      'Protein',
      'Sunscreen',
      'Sanitizer',
      'Drops',
      'Mask',
    ];
  }
}
