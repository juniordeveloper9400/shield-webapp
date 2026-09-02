import '../catalogue/catalogue_service.dart';
import '../home/product_showcase.dart';
import 'category_catalogue.dart';

/// Bridges the category screens to the live catalogue ([CatalogueService]).
///
/// The category *design* — the groups, their sub-category chips, tints and
/// banners — is still the hand-built [CategoryCatalogue]. The *products* inside
/// each group now come from `app.product` on Neon, matched to the group by its
/// category title.
///
/// When a product carries a `subcategoryLabel` — the admin filed it under one
/// of [group]'s sub-categories (see migration 0004) — the chip filters on that
/// exactly. Rows with no sub-category set (older products) fall back to a
/// keyword match on the product name so they are not lost.
class ListingCatalogue {
  const ListingCatalogue._();

  /// Every product filed under [group]'s category, newest first.
  static List<Product> forGroup(CategoryGroup group) =>
      CatalogueService.instance.byCategoryTitle(group.title);

  /// [group]'s products narrowed to one sub-category chip.
  ///
  /// A product whose `subcategoryLabel` matches [item] is always included. A
  /// product with no sub-category on record is included when its name contains
  /// one of the chip label's keywords, so a catalogue that pre-dates
  /// sub-categories still populates the chips.
  static List<Product> forSubCategoryIn(CategoryGroup group, SubCategory item) {
    final label = item.label.toLowerCase();
    final words = _keywords(item.label);
    return forGroup(group).where((p) {
      final sub = p.subcategoryLabel?.trim().toLowerCase() ?? '';
      if (sub.isNotEmpty) {
        return sub == label;
      }
      return words.any((w) => p.name.toLowerCase().contains(w));
    }).toList();
  }

  /// Whole-catalogue lookup for callers that hold only a [SubCategory] and not
  /// its group: an exact `subcategoryLabel` match, or a name keyword match for
  /// products with none.
  static List<Product> forSubCategory(SubCategory item) {
    final label = item.label.toLowerCase();
    final words = _keywords(item.label);
    return CatalogueService.instance.all.where((p) {
      final sub = p.subcategoryLabel?.trim().toLowerCase() ?? '';
      if (sub.isNotEmpty) {
        return sub == label;
      }
      return words.isNotEmpty &&
          words.any((w) => p.name.toLowerCase().contains(w));
    }).toList();
  }

  /// The steepest discounts in [products] — the listing's deals strip.
  static List<Product> topDeals(List<Product> products) {
    int percent(Product p) {
      final label = p.discountLabel;
      if (label == null) {
        return 0;
      }
      return int.tryParse(label.split('%').first.trim()) ?? 0;
    }

    final ranked = [...products]
      ..sort((a, b) => percent(b).compareTo(percent(a)));
    return ranked.take(5).toList();
  }

  /// The brand a product filters under: its own [Product.brand], or the SHIELD
  /// house brand when the admin left it blank — so every product filters under
  /// exactly one brand.
  static String brandOf(Product product) {
    final brand = product.brand?.trim() ?? '';
    return brand.isEmpty ? 'SHIELD' : brand;
  }

  /// Distinct brands across [group], alphabetically — the "Brands" facet's
  /// options.
  static List<String> brandsFor(CategoryGroup group) {
    final seen = <String>{for (final p in forGroup(group)) brandOf(p)};
    return seen.toList()..sort();
  }

  /// The group's sub-category labels, in catalogue order — the
  /// "Sub-categories" facet's options.
  static List<String> subCategoryLabels(CategoryGroup group) =>
      [for (final item in group.items) item.label];

  /// The searchable words in a sub-category label: lowercased, punctuation
  /// split out, and the noise words ("and", "care") dropped.
  static List<String> _keywords(String label) => label
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length > 2 && w != 'and' && w != 'care')
      .toList();
}
