import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import '../catalogue/catalogue_service.dart';
import '../cart/cart_control.dart';
import '../product/product_detail_screen.dart';
import 'product_collection_screen.dart';

/// A titled, horizontally scrolling row of product cards.
class ProductShowcase extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Product> products;
  final VoidCallback? onViewAll;

  const ProductShowcase({
    super.key,
    required this.title,
    required this.products,
    this.subtitle,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed:
                      onViewAll ??
                      () {
                        // Straight to this row's own products, laid out as a
                        // full grid — not the generic category browser.
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProductCollectionScreen(
                              title: title,
                              subtitle: subtitle,
                              products: products,
                            ),
                          ),
                        );
                      },
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            // Square artwork (the card's full width) plus the details block
            // below it.
            height: _ProductCard.width + _ProductCard.detailsExtent,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _ProductCard(product: products[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  static const double width = 162;

  /// Height reserved below the artwork for the name, pack, pricing and the
  /// 40px ADD / quantity control.
  static const double detailsExtent = 148;

  final Product product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      // Clipped so a product image carrying its own fill cannot square off the
      // card's rounded corners now that the thumbnail panel is gone.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      // The whole card opens the details page; the ADD / quantity control on
      // top keeps its own taps, so a shopper still adds without leaving.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  // No background of its own: the product sits directly on the
                  // card's pure white surface. Square to match the artwork, which
                  // a shorter box was letterboxing down to its own height.
                  AspectRatio(
                    aspectRatio: 1,
                    child: Padding(
                      padding: product.image != null
                          ? const EdgeInsets.all(6)
                          : EdgeInsets.zero,
                      child: Center(
                        child: AppImage(
                          image: product.image,
                          fallbackIcon: product.icon,
                          iconSize: 56,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  if (product.discountLabel != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.brandGreenDark,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.discountLabel!,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        product.pack,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            '₹${product.price}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '₹${product.mrp}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textMuted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Same control as the category listing: ADD, then an inline
                      // quantity stepper backed by the shared cart.
                      CartControl(
                        name: product.name,
                        pack: product.pack,
                        price: product.price,
                        mrp: product.mrp,
                        image: product.image,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A catalogue product as shown on a card, tile or detail page.
///
/// Cards need only the first handful of fields — name, pack, pricing, artwork.
/// The rest ([id], [brand], [categorySlug], [prescriptionOnly], [outOfStock])
/// come from `app.product` on Neon via [Product.fromRow] and are optional, so
/// the widget tests that build a [Product] by hand keep compiling.
class Product {
  final String name;
  final String pack;
  final String price;
  final String mrp;
  final String? discountLabel;
  final IconData icon;
  final String? image;

  /// `app.product.uuid`. Null for a hand-built fixture.
  final String? id;

  /// Manufacturer / brand (`app.product.brand`). `ListingCatalogue.brandOf`
  /// falls back to the house brand when this is absent.
  final String? brand;

  /// The storefront category the admin filed this under —
  /// `app.product_category.slug` / `.title`.
  final String? categorySlug;
  final String? categoryTitle;

  /// The sub-category label the admin filed this under —
  /// `app.product_subcategory.label`, e.g. `Skin Care`. Null when the admin
  /// left it unset (older rows). Matches a `SubCategory.label` in the app's
  /// `CategoryCatalogue` verbatim.
  final String? subcategoryLabel;

  /// `app.product.is_prescription_only`.
  final bool prescriptionOnly;

  /// `app.product.stock_quantity <= 0` — the card still renders, ADD is off.
  final bool outOfStock;

  /// Home-feed placement the admin set in the console (migration 0005). When
  /// no product carries a flag [CatalogueService] falls back to deriving the
  /// row, so these being all-false is the normal, seeded state.
  final bool isPopular;
  final bool isDeal;
  final bool isOfferOfDay;

  const Product({
    required this.name,
    required this.pack,
    required this.price,
    required this.mrp,
    required this.icon,
    this.image,
    this.discountLabel,
    this.id,
    this.brand,
    this.categorySlug,
    this.categoryTitle,
    this.subcategoryLabel,
    this.prescriptionOnly = false,
    this.outOfStock = false,
    this.isPopular = false,
    this.isDeal = false,
    this.isOfferOfDay = false,
  });

  /// One `app.product` row (joined to `app.product_category`) from Neon's HTTP
  /// endpoint, where every column comes back as text.
  factory Product.fromRow(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString().trim();
    double dec(Object? v) => double.tryParse(str(v)) ?? 0;
    bool flag(Object? v) {
      final s = str(v).toLowerCase();
      return s == 't' || s == 'true' || s == '1';
    }

    String? orNull(String v) => v.isEmpty ? null : v;

    final price = dec(row['price']);
    final rawMrp = dec(row['mrp']);
    final mrp = rawMrp <= 0 ? price : rawMrp;
    final slug = str(row['category_slug']);

    var discount = str(row['discount_label']);
    if (discount.isEmpty && mrp > price && price > 0) {
      discount = '${(((mrp - price) / mrp) * 100).round()}% OFF';
    }

    return Product(
      id: orNull(str(row['uuid'])),
      name: str(row['name']),
      pack: str(row['pack']),
      brand: orNull(str(row['brand'])),
      categorySlug: orNull(slug),
      categoryTitle: orNull(str(row['category_title'])),
      subcategoryLabel: orNull(str(row['subcategory_label'])),
      price: formatRupees(price.round()),
      mrp: formatRupees(mrp.round()),
      discountLabel: orNull(discount),
      icon: iconForCategorySlug(slug),
      image: orNull(str(row['image'])),
      prescriptionOnly: flag(row['is_prescription_only']),
      outOfStock: dec(row['stock_quantity']) <= 0,
      isPopular: flag(row['is_popular']),
      isDeal: flag(row['is_deal']),
      isOfferOfDay: flag(row['is_offer_of_day']),
    );
  }
}

/// A stand-in icon for a product with no artwork of its own — the admin
/// console does not capture product images yet, so every catalogue product
/// falls back to its category's icon.
IconData iconForCategorySlug(String? slug) {
  switch (slug) {
    case 'personal-care':
      return Icons.spa_outlined;
    case 'health-conditions':
      return Icons.monitor_heart_outlined;
    case 'vitamins-supplements':
      return Icons.medication_outlined;
    case 'diabetes-care':
      return Icons.bloodtype_outlined;
    case 'surgicals':
      return Icons.medical_services_outlined;
    case 'lab-tests':
      return Icons.biotech_outlined;
    default:
      return Icons.medication_outlined;
  }
}

/// The home showcases, now backed by the live catalogue ([CatalogueService])
/// instead of a hand-written list. Each getter is a snapshot of the current
/// catalogue; the home screen listens to [CatalogueService] and rebuilds these
/// rows as products load in from Neon.
class ProductCatalogue {
  const ProductCatalogue._();

  /// Admin-picked "Popular Items", or the newest products as a fallback.
  static List<Product> get popularItems =>
      CatalogueService.instance.popularPicks;

  /// Admin-picked "Deals You Love", or the steepest discounts as a fallback.
  static List<Product> get dealsYouLove =>
      CatalogueService.instance.dealsYouLove;

  /// Admin-picked "Offer of the Day" — empty until the admin ticks products.
  static List<Product> get offerOfTheDay =>
      CatalogueService.instance.offerOfTheDay;

  /// The "Vitamins & Supplements" category.
  static List<Product> get wellnessAndSupplements =>
      CatalogueService.instance.wellness;

  static List<Product> get wellness => wellnessAndSupplements;
}
