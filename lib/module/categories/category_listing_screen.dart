import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import '../cart/cart_bar.dart';
import '../cart/cart_control.dart';
import '../cart/cart_screen.dart';
import '../cart/cart_service.dart';
import '../catalogue/catalogue_service.dart';
import '../home/product_showcase.dart';
import '../product/product_detail_screen.dart';
import '../search/search_screen.dart';
import 'category_catalogue.dart';
import 'listing_catalogue.dart';
import 'listing_filter.dart';

/// Product listing for one category group.
///
/// Opens on the sub-category that was tapped, with a chip rail for switching
/// between the rest of the group and an "All" chip covering every item.
class CategoryListingScreen extends StatefulWidget {
  final CategoryGroup group;
  final SubCategory? initial;

  const CategoryListingScreen({super.key, required this.group, this.initial});

  @override
  State<CategoryListingScreen> createState() => _CategoryListingScreenState();
}

class _CategoryListingScreenState extends State<CategoryListingScreen> {
  /// Null means the "All" chip.
  SubCategory? _selected;

  /// The filter sheet's applied state. Starts as the do-nothing filter.
  ListingFilter _filter = ListingFilter.none;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    CatalogueService.instance.ensureLoaded();
  }

  /// What the grid shows: the chip rail's selection with the filter sheet's
  /// sub-category and brand picks applied on top.
  List<Product> get _products => _filter.resolve(widget.group, chip: _selected);

  Future<void> _openFilter() async {
    final result = await showListingFilterSheet(
      context,
      group: widget.group,
      current: _filter,
    );
    if (result != null) {
      setState(() {
        _filter = result;
        // Once the sheet drives the sub-category, the single-pick chip rail
        // steps back to "All" so the two selections can't contradict.
        if (result.subCategories.isNotEmpty) {
          _selected = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogueService.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final products = _products;
    final deals = ListingCatalogue.topDeals(products);
    final catalogue = CatalogueService.instance;
    final loadingFirst = products.isEmpty && !catalogue.isSettled;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          widget.group.title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        actions: [
          _CircleAction(
            icon: Icons.search_rounded,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          const SizedBox(width: 10),
          _CartAction(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CartScreen())),
          ),
          const SizedBox(width: 12),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _ListingBanner(group: widget.group)),
              // Chip rail + filter strip: pinned, so switching sub-category or
              // opening the filter stays one reach away however far the grid
              // has scrolled.
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeader(
                  child: Column(
                    children: [
                      _ChipRail(
                        group: widget.group,
                        selected: _selected,
                        onSelect: (item) => setState(() {
                          _selected = item;
                          // A tap on the rail takes back the sub-category pick
                          // from the filter sheet; brand picks are left alone.
                          _filter = _filter.copyWith(subCategories: const {});
                        }),
                      ),
                      _FilterRow(
                        resultCount: products.length,
                        onTap: _openFilter,
                        activeCount: _filter.count,
                      ),
                    ],
                  ),
                ),
              ),
              if (loadingFirst)
                const SliverToBoxAdapter(child: _ListingLoading())
              else if (products.isEmpty)
                SliverToBoxAdapter(
                  child: _NoMatches(
                    catalogueEmpty: !catalogue.hasProducts,
                    onClear: () => setState(() => _filter = ListingFilter.none),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(_gridPad, 14, _gridPad, 8),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: _gridGap,
                      // A square of artwork plus a fixed block for the details,
                      // rather than one ratio for the whole tile. The details
                      // need the same height at every width, so a ratio starves
                      // them on a narrow phone and leaves a band of dead space
                      // on a wide one — which is what was shrinking the image.
                      mainAxisExtent:
                          _gridColumnWidth(context) + ProductTile.detailsExtent,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => ProductTile(product: products[index]),
                      childCount: products.length,
                    ),
                  ),
                ),
              if (deals.isNotEmpty)
                SliverToBoxAdapter(child: _TopDealsPanel(deals: deals)),
              // Clears the floating cart bar so the last row stays reachable.
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: CartBar()),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.searchBorder),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 21, color: AppColors.textDark),
        ),
      ),
    );
  }
}

/// Cart circle with the live item count.
class _CartAction extends StatelessWidget {
  final VoidCallback onTap;

  const _CartAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartService.instance,
      builder: (context, _) {
        final count = CartService.instance.itemCount;
        return Semantics(
          button: true,
          label: count == 0 ? 'Cart' : 'Cart · $count items',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _CircleAction(icon: Icons.shopping_cart_outlined, onTap: onTap),
              if (count > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD93A2B),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
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
        );
      },
    );
  }
}

class _ListingBanner extends StatelessWidget {
  final CategoryGroup group;

  const _ListingBanner({required this.group});

  @override
  Widget build(BuildContext context) {
    if (group.bannerImage != null) {
      final isNetwork = AppImage.isNetwork(group.bannerImage);
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        height: 152,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: isNetwork
            ? Image.network(
                group.bannerImage!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 152,
                errorBuilder: (_, _, _) => _buildGradientBanner(),
              )
            : Image.asset(
                group.bannerImage!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 152,
                errorBuilder: (_, _, _) => _buildGradientBanner(),
              ),
      );
    }

    return _buildGradientBanner();
  }

  Widget _buildGradientBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      height: 152,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [AppColors.brandBlue, AppColors.brandNavy],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -20,
            child: Icon(
              group.icon,
              size: 150,
              color: AppColors.white.withValues(alpha: 0.10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandGreen,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Up to 20% off',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  group.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Trusted brands, delivered to your door',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.3,
                    color: Color(0xFFC9D8F0),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular sub-category chips with an underline under the active one.
class _ChipRail extends StatelessWidget {
  final CategoryGroup group;
  final SubCategory? selected;
  final ValueChanged<SubCategory?> onSelect;

  const _ChipRail({
    required this.group,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        height: 128,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: group.items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _RailChip(
                label: 'All',
                icon: group.icon,
                image: group.image,
                isSelected: selected == null,
                onTap: () => onSelect(null),
              );
            }
            final item = group.items[index - 1];
            return _RailChip(
              label: item.label,
              icon: item.icon,
              image: item.image,
              isSelected: selected?.label == item.label,
              onTap: () => onSelect(item),
            );
          },
        ),
      ),
    );
  }
}

class _RailChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? image;
  final bool isSelected;
  final VoidCallback onTap;

  const _RailChip({
    required this.label,
    required this.icon,
    required this.image,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.offerTint : AppColors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.offerTint : AppColors.border,
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: AppImage(
                image: image,
                fallbackIcon: icon,
                iconSize: 26,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
            ),
            // Underline marks the active chip, as in the reference.
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue : AppColors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Height of the pinned strip carrying the chip rail (129) and the filter
/// bar (52).
const double _stickyHeaderExtent = 181;

/// Horizontal padding either side of the product grid.
const double _gridPad = 12;

/// Gap between the grid's two columns.
const double _gridGap = 12;

/// Width of one grid column at this viewport.
double _gridColumnWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width - _gridPad * 2 - _gridGap) / 2;

/// Grid tile: discount flag, artwork, name, pricing, and the cart control.
class ProductTile extends StatelessWidget {
  /// Height reserved below the artwork for the name, pack, pricing and cart
  /// control. Fixed, because that stack is the same height at every tile
  /// width — the grid adds it to the square artwork to size the whole tile.
  static const double detailsExtent = 138;

  final Product product;

  const ProductTile({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      // The tile opens the product's details page; the ADD / quantity control
      // sitting on it keeps its own taps.
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
              // Square, because the product artwork is square: contained in a
              // wider-than-tall box it was limited by the short side and sat
              // with a gutter down either edge, making it read as small.
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AppImage(
                          image: product.image,
                          fallbackIcon: product.icon,
                          iconSize: 56,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    if (product.discountLabel != null)
                      _DiscountFlag(label: product.discountLabel!),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.2,
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
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '₹${product.price}',
                            style: const TextStyle(
                              fontSize: 15.5,
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
                                fontSize: 12,
                                color: AppColors.textMuted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
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

class _DiscountFlag extends StatelessWidget {
  final String label;

  const _DiscountFlag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 6),
      decoration: const BoxDecoration(
        color: AppColors.brandGreenDark,
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
      ),
      child: Text(
        label.replaceAll(' OFF', '\nOFF'),
        style: const TextStyle(
          fontSize: 11,
          height: 1.15,
          fontWeight: FontWeight.w800,
          color: AppColors.white,
        ),
      ),
    );
  }
}

/// "Top deals": a featured product with a thumbnail rail to switch between
/// the rest of the discounted stock.
class _TopDealsPanel extends StatefulWidget {
  final List<Product> deals;

  const _TopDealsPanel({required this.deals});

  @override
  State<_TopDealsPanel> createState() => _TopDealsPanelState();
}

class _TopDealsPanelState extends State<_TopDealsPanel> {
  int _featured = 0;

  @override
  Widget build(BuildContext context) {
    // A shorter list after a chip change can leave the old index dangling.
    final featured = widget.deals[_featured.clamp(0, widget.deals.length - 1)];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.offerTint,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top deals',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          _FeaturedDeal(product: featured),
          const SizedBox(height: 14),
          SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.deals.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final deal = widget.deals[index];
                final isActive = deal.name == featured.name;
                return InkWell(
                  onTap: () => setState(() => _featured = index),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isActive
                            ? AppColors.brandBlue
                            : AppColors.border,
                        width: isActive ? 1.8 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: AppImage(
                      image: deal.image,
                      fallbackIcon: deal.icon,
                      iconSize: 24,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedDeal extends StatelessWidget {
  final Product product;

  const _FeaturedDeal({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                // Wider and less padded than it was, so the square artwork is
                // limited by the row's height rather than by its own box.
                width: 124,
                height: 132,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: AppImage(
                          image: product.image,
                          fallbackIcon: product.icon,
                          iconSize: 46,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    if (product.discountLabel != null)
                      _DiscountFlag(label: product.discountLabel!),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '₹${product.mrp}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textMuted,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                Text(
                                  '₹${product.price}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 108,
                            child: CartControl(
                              name: product.name,
                              pack: product.pack,
                              price: product.price,
                              mrp: product.mrp,
                              image: product.image,
                            ),
                          ),
                        ],
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

/// The strip that sits between the chip rail and the grid: how many products
/// are in view on the left, the "Filter" affordance on the right.
class _FilterRow extends StatelessWidget {
  final int resultCount;
  final VoidCallback onTap;
  final int activeCount;

  const _FilterRow({
    required this.resultCount,
    required this.onTap,
    required this.activeCount,
  });

  @override
  Widget build(BuildContext context) {
    // Fixed height, because it is half of the pinned header's declared extent.
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: _gridPad),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              resultCount == 1 ? '1 product' : '$resultCount products',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          _FilterPill(onTap: onTap, activeCount: activeCount),
        ],
      ),
    );
  }
}

/// Pins the chip rail and filter bar to the top of the listing while the grid
/// scrolls beneath them.
class _StickyHeader extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _StickyHeader({required this.child});

  @override
  double get minExtent => _stickyHeaderExtent;

  @override
  double get maxExtent => _stickyHeaderExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: AppColors.white,
      elevation: overlapsContent ? 3 : 0,
      shadowColor: AppColors.textDark.withValues(alpha: 0.15),
      child: SizedBox(height: _stickyHeaderExtent, child: child),
    );
  }

  // The child closes over the current selection and filter, so it is a fresh
  // widget on every rebuild.
  @override
  bool shouldRebuild(_StickyHeader oldDelegate) => true;
}

/// "Filter" affordance. Carries a count badge once the sheet has narrowed the
/// listing, so an active filter is visible without opening it.
class _FilterPill extends StatelessWidget {
  final VoidCallback onTap;
  final int activeCount;

  const _FilterPill({required this.onTap, required this.activeCount});

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;

    return Material(
      color: active ? AppColors.brandBlue : AppColors.white,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: active ? AppColors.brandBlue : AppColors.searchBorder,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 9, 18, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 18,
                color: active ? AppColors.white : AppColors.textDark,
              ),
              const SizedBox(width: 8),
              Text(
                active ? 'Filter · $activeCount' : 'Filter',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.white : AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the grid when the filter leaves nothing to list.
/// Fills the grid area while the catalogue is loading for the first time.
class _ListingLoading extends StatelessWidget {
  const _ListingLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 72, 32, 72),
      child: Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.brandBlue,
          ),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  final VoidCallback onClear;

  /// True when the whole catalogue is empty or unreachable — not just that the
  /// current filters exclude everything. The copy and the action differ.
  final bool catalogueEmpty;

  const _NoMatches({required this.onClear, this.catalogueEmpty = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 64),
      child: Column(
        children: [
          Icon(
            catalogueEmpty
                ? Icons.inventory_2_outlined
                : Icons.filter_alt_off_outlined,
            size: 44,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 14),
          Text(
            catalogueEmpty
                ? 'No products in this category yet'
                : 'No products match your filters',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            catalogueEmpty
                ? 'Check back once the pharmacy has stocked this shelf.'
                : 'Try removing a sub-category or brand.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          if (!catalogueEmpty) ...[
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: onClear,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandBlue,
                side: const BorderSide(color: AppColors.brandBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }
}
