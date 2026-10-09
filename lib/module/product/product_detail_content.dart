import 'dart:convert';

import '../../money.dart';
import '../categories/listing_catalogue.dart';
import '../home/product_showcase.dart';

/// One question and its answer in the details page's FAQ list.
class ProductFaq {
  final String question;
  final String answer;

  const ProductFaq(this.question, this.answer);
}

/// Admin-entered detail content for one product, read from `app.product_detail`
/// and `app.product_faq` in the console.
///
/// Every field is optional. Whatever the pharmacy admin left blank is filled in
/// by the generated text in [ProductDetail], so a half-filled form still yields
/// a complete page and an all-blank one reads exactly as it did before the
/// console captured any of this.
class ProductDetailData {
  final String? form;
  final String? manufacturer;
  final String description;
  final String ingredients;
  final String storage;
  final List<String> highlights;
  final List<String> benefits;
  final List<String> directions;
  final List<String> safety;
  final List<ProductFaq> faqs;

  const ProductDetailData({
    this.form,
    this.manufacturer,
    this.description = '',
    this.ingredients = '',
    this.storage = '',
    this.highlights = const [],
    this.benefits = const [],
    this.directions = const [],
    this.safety = const [],
    this.faqs = const [],
  });

  /// True when the admin has entered nothing at all — the page is then 100%
  /// generated and this override can be ignored.
  bool get isEmpty =>
      (form == null || form!.trim().isEmpty) &&
      (manufacturer == null || manufacturer!.trim().isEmpty) &&
      description.trim().isEmpty &&
      ingredients.trim().isEmpty &&
      storage.trim().isEmpty &&
      highlights.isEmpty &&
      benefits.isEmpty &&
      directions.isEmpty &&
      safety.isEmpty &&
      faqs.isEmpty;

  /// Builds from one `app.product_detail` row (or null) plus its FAQ rows, as
  /// they come back from Neon's HTTP endpoint — every scalar a string, every
  /// array column pre-wrapped as a JSON string by `to_json(...)` in the query.
  factory ProductDetailData.fromRows(
    Map<String, dynamic>? detail,
    Object? faqsJson,
  ) {
    String str(Object? v) => (v ?? '').toString().trim();

    List<String> list(Object? v) {
      if (v == null) return const [];
      if (v is List) {
        return v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
      final raw = v.toString().trim();
      if (raw.isEmpty || raw == '[]' || raw == '{}') return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {
        // Fall through to the Postgres array-literal form: {"a","b"}.
      }
      return raw
          .replaceAll(RegExp(r'^\{|\}$'), '')
          .split(',')
          .map((e) => e.replaceAll(RegExp(r'^"|"$'), '').trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    final faqs = <ProductFaq>[];
    if (faqsJson != null) {
      final raw = faqsJson is String ? faqsJson : jsonEncode(faqsJson);
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final q = str(item['q'] ?? item['question']);
              final a = str(item['a'] ?? item['answer']);
              if (q.isNotEmpty && a.isNotEmpty) faqs.add(ProductFaq(q, a));
            }
          }
        }
      } catch (_) {
        // No FAQs rather than a crash on malformed JSON.
      }
    }

    String? orNull(String v) => v.isEmpty ? null : v;

    return ProductDetailData(
      form: orNull(str(detail?['form'])),
      manufacturer: orNull(str(detail?['manufacturer'])),
      description: str(detail?['description']),
      ingredients: str(detail?['ingredients']),
      storage: str(detail?['storage']),
      highlights: list(detail?['highlights']),
      benefits: list(detail?['benefits']),
      directions: list(detail?['directions']),
      safety: list(detail?['safety']),
      faqs: faqs,
    );
  }
}

/// What a product physically is, inferred from its name and pack.
///
/// The catalogue never says whether a line is a tablet, a face wash or a
/// blood-pressure monitor, but the details page has to — an oral medicine must
/// not read like a cream. Every generated paragraph branches on this.
enum ProductForm {
  oral,
  supplement,
  topical,
  cleanser,
  sunscreen,
  device,
  generic,
}

/// The long-form content behind a [Product] on its details page.
///
/// The fixtures carry only what a grid tile needs — name, pack, pricing and
/// artwork. A details page needs paragraphs the fixtures do not hold, so they
/// are composed here from the product's name and pack. The mapping is pure and
/// deterministic: the same product always reads the same, and a widget test can
/// assert on any line of it.
class ProductDetail {
  final Product product;
  final ProductForm form;
  final String manufacturer;
  final List<String> highlights;
  final String description;
  final List<String> benefits;
  final List<String> directions;
  final List<String> safety;
  final String ingredients;
  final String storage;
  final List<ProductFaq> faqs;

  const ProductDetail._({
    required this.product,
    required this.form,
    required this.manufacturer,
    required this.highlights,
    required this.description,
    required this.benefits,
    required this.directions,
    required this.safety,
    required this.ingredients,
    required this.storage,
    required this.faqs,
  });

  /// The details-page content for [product] — entirely what the pharmacy
  /// admin typed into the console's product form (`app.product_detail` /
  /// `app.product_faq`). Nothing here is invented: a field the admin left
  /// blank stays blank, and [ProductDetailScreen] hides that section rather
  /// than showing made-up copy. Pass `null` (or an all-blank
  /// [ProductDetailData]) for a product nobody has added detail to yet — the
  /// page then shows only the artwork and ADD, the one thing every product
  /// always has.
  factory ProductDetail.of(Product product, {ProductDetailData? content}) {
    final admin = (content == null || content.isEmpty) ? null : content;

    final form = _formFromLabel(admin?.form) ?? _formOf(product);
    // Not invented copy — [ListingCatalogue.brandOf] is the house's own
    // mapping of a product to its real manufacturer, the fallback the
    // catalogue grid already shows when the admin hasn't typed one in here.
    final manufacturer = admin?.manufacturer?.trim().isNotEmpty == true
        ? admin!.manufacturer!.trim()
        : ListingCatalogue.brandOf(product);

    return ProductDetail._(
      product: product,
      form: form,
      manufacturer: manufacturer,
      highlights: admin?.highlights ?? const [],
      description: admin?.description.trim() ?? '',
      benefits: admin?.benefits ?? const [],
      directions: admin?.directions ?? const [],
      safety: admin?.safety ?? const [],
      ingredients: admin?.ingredients.trim() ?? '',
      storage: admin?.storage.trim() ?? '',
      faqs: admin?.faqs ?? const [],
    );
  }

  /// Maps a free-text form label the admin typed ("tablet", "syrup", "cream",
  /// "device", …) onto a [ProductForm]. Null for a blank or unrecognised label,
  /// so the caller falls back to inferring it from the name.
  static ProductForm? _formFromLabel(String? label) {
    final text = (label ?? '').toLowerCase().trim();
    if (text.isEmpty) return null;
    bool has(List<String> keys) => keys.any(text.contains);
    if (has(['device', 'monitor', 'meter', 'machine'])) {
      return ProductForm.device;
    }
    if (has(['sunscreen', 'spf', 'sun '])) return ProductForm.sunscreen;
    if (has(['wash', 'shampoo', 'soap', 'cleanser', 'rinse'])) {
      return ProductForm.cleanser;
    }
    if (has([
      'supplement',
      'vitamin',
      'protein',
      'mineral',
      'nutrition',
      'powder',
    ])) {
      return ProductForm.supplement;
    }
    if (has([
      'cream',
      'gel',
      'lotion',
      'ointment',
      'oil',
      'serum',
      'balm',
      'spray',
      'drops',
      'topical',
    ])) {
      return ProductForm.topical;
    }
    if (has(['tablet', 'capsule', 'syrup', 'sachet', 'suspension', 'oral'])) {
      return ProductForm.oral;
    }
    return null;
  }

  // ---- derived pricing ----

  double get _price => _num(product.price);

  double get _mrp {
    final m = _num(product.mrp);
    return m <= 0 ? _price : m;
  }

  /// Rupees off the MRP. Never negative, even if a fixture quotes a price above
  /// its own MRP.
  double get save {
    final gap = _mrp - _price;
    return gap > 0 ? gap : 0;
  }

  int get discountPercent => _discount(product);

  String get priceLabel => '₹${_money(_price)}';
  String get mrpLabel => '₹${_money(_mrp)}';
  String get saveLabel => '₹${_money(save)}';

  /// "₹0.79/unit" when the pack names a countable number of units, else null —
  /// a per-unit price on a single tube of gel would be meaningless.
  String? get unitPriceLabel {
    final count = _packCount(product.pack);
    if (count == null || count < 2) {
      return null;
    }
    if (form != ProductForm.oral && form != ProductForm.supplement) {
      return null;
    }
    return '₹${(_price / count).toStringAsFixed(2)}/unit';
  }

  // ---- helpers ----

  static double _num(String value) =>
      double.tryParse(value.replaceAll(',', '').trim()) ?? 0;

  /// Whole rupees keep Indian grouping; a fractional value keeps two places.
  static String _money(double value) => value == value.roundToDouble()
      ? formatRupees(value.round())
      : value.toStringAsFixed(2);

  static int _discount(Product product) {
    final price = _num(product.price);
    final mrp = _num(product.mrp);
    if (mrp <= 0 || mrp <= price) {
      return 0;
    }
    return ((mrp - price) / mrp * 100).round();
  }

  /// The first run of digits in a pack string: "Strip of 30 tablets" → 30,
  /// "1 device" → 1, "Bottle of 125ml" → 125.
  static int? _packCount(String pack) {
    final match = RegExp(r'\d[\d,]*').firstMatch(pack);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(0)!.replaceAll(',', ''));
  }

  static ProductForm _formOf(Product product) {
    final text = '${product.name} ${product.pack}'.toLowerCase();
    bool has(List<String> keys) => keys.any(text.contains);

    if (has([
      'device',
      'monitor',
      'glucometer',
      'oximeter',
      'thermometer',
      'nebulizer',
      'nebuliser',
      'needles',
      'test strip',
    ])) {
      return ProductForm.device;
    }
    if (has(['sunscreen', 'spf'])) {
      return ProductForm.sunscreen;
    }
    if (has([
      'wash',
      'shampoo',
      'conditioner',
      'soap',
      'shower gel',
      'body wash',
      'scrub',
      'mouthwash',
      'rinse',
      'cleanser',
    ])) {
      return ProductForm.cleanser;
    }
    if (has([
      'protein',
      'multivitamin',
      'vitamin',
      'omega',
      'fish oil',
      'calcium',
      'immunity',
      'biotin',
      'collagen',
      'gainer',
      'creatine',
      'supplement',
    ])) {
      return ProductForm.supplement;
    }
    if (has([
      'gel',
      'cream',
      'lotion',
      'oil',
      'serum',
      'balm',
      'ointment',
      'moisturiz',
      'moisturis',
      'patch',
      'mask',
      'spray',
      'drops',
    ])) {
      return ProductForm.topical;
    }
    if (has(['tablet', 'capsule', 'syrup', 'sachet', 'powder', 'suspension'])) {
      return ProductForm.oral;
    }
    return ProductForm.generic;
  }
}
