import '../../money.dart';
import '../categories/listing_catalogue.dart';
import '../home/product_showcase.dart';

/// One question and its answer in the details page's FAQ list.
class ProductFaq {
  final String question;
  final String answer;

  const ProductFaq(this.question, this.answer);
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

  factory ProductDetail.of(Product product) {
    final form = _formOf(product);
    final manufacturer = ListingCatalogue.brandOf(product);
    final short = _shortName(product.name);
    final discount = _discount(product);

    return ProductDetail._(
      product: product,
      form: form,
      manufacturer: manufacturer,
      highlights: _highlights(product, manufacturer, discount),
      description: _description(product, manufacturer, form, short),
      benefits: _benefits(form),
      directions: _directions(form),
      safety: _safety(form),
      ingredients: _ingredients(form),
      storage: _storage(form),
      faqs: _faqs(short, form, manufacturer),
    );
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

  /// The product name with trailing size tokens ("100ml", "60K", "500") pruned,
  /// capped at four words — what a sentence or a FAQ heading should call it.
  static String _shortName(String name) {
    final size = RegExp(
      r'^\d+(\.\d+)?(ml|g|gm|mg|kg|l|iu|s|k|count|pack)?$',
      caseSensitive: false,
    );
    final words = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !size.hasMatch(word))
        .toList();
    final short = words.take(4).join(' ').trim();
    return short.isEmpty ? name : short;
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

  static String _formWord(ProductForm form) {
    switch (form) {
      case ProductForm.oral:
        return 'an oral formulation';
      case ProductForm.supplement:
        return 'a nutritional supplement';
      case ProductForm.topical:
        return 'a topical application';
      case ProductForm.cleanser:
        return 'a cleansing product';
      case ProductForm.sunscreen:
        return 'a sun-protection product';
      case ProductForm.device:
        return 'a home health device';
      case ProductForm.generic:
        return 'an everyday-use product';
    }
  }

  static String _verb(ProductForm form) =>
      form == ProductForm.oral || form == ProductForm.supplement
      ? 'take'
      : 'use';

  static List<String> _highlights(
    Product product,
    String manufacturer,
    int discount,
  ) => [
    if (discount > 0) 'Flat $discount% off the printed MRP',
    '100% genuine, sourced from $manufacturer or an authorised distributor',
    'Sealed pack, stored and shipped in temperature-controlled conditions',
    'Delivered across India by Sahakar 360 Pharmacy',
  ];

  static String _description(
    Product product,
    String manufacturer,
    ProductForm form,
    String short,
  ) {
    final lead =
        '$short is ${_formWord(form)}'
        '${form == ProductForm.device ? '' : ' from $manufacturer'}, '
        'supplied as ${_articleFor(product.pack)}.';

    final middle = switch (form) {
      ProductForm.oral =>
        ' It delivers a measured dose in every unit, so a course stays '
            'consistent from the first day to the last.',
      ProductForm.supplement =>
        ' It is meant to top up a daily nutritional gap alongside a balanced '
            'diet, not to replace one.',
      ProductForm.topical =>
        ' It works where it is applied, which keeps the rest of the body out '
            'of the picture.',
      ProductForm.cleanser =>
        ' It lifts away dirt, oil and build-up and rinses off without leaving '
            'the skin feeling tight.',
      ProductForm.sunscreen =>
        ' It forms a light, broad-spectrum layer that guards against UVA and '
            'UVB rays through the day.',
      ProductForm.device =>
        ' It lets you take a reading at home, on your own schedule, and keep '
            'a record between clinic visits.',
      ProductForm.generic => ' It is a dependable pick for everyday use.',
    };

    return '$lead$middle '
        'Every order on Sahakar 360 is genuine and within its shelf life.';
  }

  static String _articleFor(String pack) {
    final lower = pack.toLowerCase();
    return RegExp(r'^[aeiou]').hasMatch(lower) ? 'an $lower' : 'a $lower';
  }

  static List<String> _benefits(ProductForm form) {
    switch (form) {
      case ProductForm.oral:
        return const [
          'Targeted relief for the condition it was prescribed for',
          'Predictable, measured dosing in every strip',
          'Well tolerated by most adults when taken as directed',
        ];
      case ProductForm.supplement:
        return const [
          'Helps close a daily gap in vitamins, minerals or protein',
          'Supports everyday energy, immunity and recovery',
          'Simple to fold into an existing routine',
        ];
      case ProductForm.topical:
        return const [
          'Acts directly on the affected area',
          'Absorbs in without a heavy or greasy residue',
          'Suitable for regular use on most skin types',
        ];
      case ProductForm.cleanser:
        return const [
          'Clears away dirt, oil and product build-up',
          'Rinses clean without over-drying the skin',
          'Gentle enough for daily use',
        ];
      case ProductForm.sunscreen:
        return const [
          'Broad-spectrum cover against UVA and UVB rays',
          'Lightweight, non-greasy finish under make-up or on bare skin',
          'Helps prevent tanning, dark spots and sun damage',
        ];
      case ProductForm.device:
        return const [
          'Take readings at home, whenever you need one',
          'Clear digital display that is easy to read',
          'Compact enough to keep by the bed or carry when travelling',
        ];
      case ProductForm.generic:
        return const [
          'A dependable choice for everyday needs',
          'Quality-checked before it ships',
          'From a brand people recognise',
        ];
    }
  }

  static List<String> _directions(ProductForm form) {
    switch (form) {
      case ProductForm.oral:
        return const [
          'Take exactly as directed by your doctor or pharmacist.',
          'Swallow whole with a glass of water — do not crush or chew unless '
              'told to.',
          'Try to take it at the same time each day.',
          'Do not stop early, and never double up on a missed dose.',
        ];
      case ProductForm.supplement:
        return const [
          'Take one serving a day, or as directed on the label.',
          'Best taken with or just after a meal.',
          'Do not exceed the recommended daily amount.',
        ];
      case ProductForm.topical:
        return const [
          'Clean and dry the area before use.',
          'Apply a thin layer and massage in gently.',
          'Use two to three times a day, or as advised.',
          'Wash your hands afterwards, unless you are treating them.',
        ];
      case ProductForm.cleanser:
        return const [
          'Apply to wet skin or hair.',
          'Massage into a light lather, then rinse thoroughly with water.',
          'Use once or twice a day.',
          'Avoid contact with the eyes.',
        ];
      case ProductForm.sunscreen:
        return const [
          'Apply generously to all exposed skin 15 minutes before going out.',
          'Reapply every 3 hours, and after swimming or sweating.',
          'Use as the last step of your skincare, before make-up.',
        ];
      case ProductForm.device:
        return const [
          'Read the instruction manual fully before the first use.',
          'Rest and sit still for five minutes before taking a reading.',
          'Wipe the device with a dry cloth after use.',
          'Replace batteries or consumables as the manual specifies.',
        ];
      case ProductForm.generic:
        return const [
          'Use as directed on the pack.',
          'Follow any instructions from your doctor or pharmacist.',
        ];
    }
  }

  static List<String> _safety(ProductForm form) {
    const tail = [
      'Keep out of the reach of children.',
      'Do not use after the printed expiry date.',
    ];
    switch (form) {
      case ProductForm.oral:
      case ProductForm.supplement:
        return const [
          'Tell your doctor about any other medicines, supplements or '
              'conditions before starting.',
          'Speak to your doctor first if you are pregnant or breastfeeding.',
          ...tail,
        ];
      case ProductForm.topical:
      case ProductForm.cleanser:
      case ProductForm.sunscreen:
        return const [
          'For external use only.',
          'Do a patch test first if your skin is sensitive.',
          'Stop use and seek advice if irritation, redness or a rash appears.',
          ...tail,
        ];
      case ProductForm.device:
        return const [
          'Readings support, but do not replace, advice from your doctor.',
          'Keep the device dry and away from strong magnetic fields.',
          ...tail,
        ];
      case ProductForm.generic:
        return const ['Use only as intended.', ...tail];
    }
  }

  static String _ingredients(ProductForm form) {
    switch (form) {
      case ProductForm.oral:
        return 'Active pharmaceutical ingredients as printed on the pack, with '
            'standard binders, fillers and coating agents.';
      case ProductForm.supplement:
        return 'A blend of vitamins, minerals and/or nutrients as printed on '
            'the label, with food-grade excipients.';
      case ProductForm.topical:
        return 'Active compounds in a skin-friendly base of emollients, '
            'humectants and stabilisers.';
      case ProductForm.cleanser:
        return 'Mild surfactants and conditioning agents in a water base, with '
            'fragrance and preservatives.';
      case ProductForm.sunscreen:
        return 'Broad-spectrum UV filters in a light, fast-absorbing emulsion.';
      case ProductForm.device:
        return 'Not applicable — this is a device, not a consumable.';
      case ProductForm.generic:
        return 'See the pack for the full ingredient list.';
    }
  }

  static String _storage(ProductForm form) => form == ProductForm.device
      ? 'Store in a clean, dry place away from direct sunlight. Handle with '
            'care.'
      : 'Store below 30°C in a dry place, away from direct sunlight. Keep out '
            'of reach of children.';

  static List<ProductFaq> _faqs(
    String short,
    ProductForm form,
    String manufacturer,
  ) {
    final verb = _verb(form);
    return [
      ProductFaq(
        'What is $short used for?',
        '${_benefits(form).first}. Always follow the advice your doctor or '
            'pharmacist gives for your own situation.',
      ),
      ProductFaq('How should I $verb $short?', _directions(form).first),
      ProductFaq('Are there any precautions?', _safety(form).first),
      ProductFaq(
        'Is $short genuine on Sahakar 360?',
        'Yes. Every order is sourced from $manufacturer or an authorised '
            'distributor, sealed, and shipped in temperature-controlled '
            'conditions.',
      ),
    ];
  }
}
