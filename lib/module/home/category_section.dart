import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../categories/categories_screen.dart';
import '../../widgets/app_image.dart';
import '../categories/category_card.dart';
import '../categories/category_catalogue.dart';
import '../categories/category_listing_screen.dart';

/// "Shop by categories" block: a row of selectable category chips above a
/// panel of sub-category cards for whichever chip is active.
///
/// Draws from [CategoryCatalogue] and renders [CategoryCard], the same data
/// and the same card the Categories tab uses. The only difference here is the
/// chip strip and the panel's square top, which lets the active chip merge
/// into the panel below it.
class CategorySection extends StatefulWidget {
  const CategorySection({super.key});

  @override
  State<CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<CategorySection> {
  /// The group the strip opens on, resolved by name so reordering the rail
  /// cannot silently change which one is selected first.
  ///
  /// Wellness, because the strip below it sells wellness. Its six
  /// sub-categories are the six products in that strip — Multivitamins,
  /// Vitamin D, Protein Powder, Omega & Fish Oil, Calcium and Immunity —
  /// so what the reader taps into is what they have just been shown.
  /// Opening on Personal Care put skin, hair and oral care above a row of
  /// supplements, which answered a question nobody had asked.
  static const String _initialGroup = 'Vitamins & Supplements';

  late int _selected = _groups.indexWhere(
    (group) => group.title == _initialGroup,
  );

  List<CategoryGroup> get _groups => CategoryCatalogue.shoppable;

  @override
  void initState() {
    super.initState();
    // The backend copy can still be loading (main.dart's ensureLoaded) the
    // moment this strip first paints — ask again and refresh once it lands.
    CategoryCatalog.instance.addListener(_onCatalogChanged);
    CategoryCatalog.instance.ensureLoaded();
  }

  @override
  void dispose() {
    CategoryCatalog.instance.removeListener(_onCatalogChanged);
    super.dispose();
  }

  /// The live groups can arrive with a different shape than whatever
  /// [_selected] was resolved against (the seed) — re-find the opening group
  /// by name, or fall back to the first one rather than an index that no
  /// longer lines up.
  void _onCatalogChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      final match = _groups.indexWhere((group) => group.title == _initialGroup);
      _selected = match >= 0 ? match : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    // Only reachable if an admin retitles every strip category away from
    // _stripOrder at once — nothing left to show rather than a crash.
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }
    final active = groups[_selected.clamp(0, groups.length - 1)];

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Shop by categories',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                TextButton(
                  // The way into the full catalogue now that Categories is a
                  // route rather than a tab.
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
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
          // A scrolling rail rather than a fixed Row: five groups cannot share
          // a phone's width as equal columns without the labels collapsing.
          SizedBox(
            height: 122,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _groups.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _CategoryPill(
                group: _groups[index],
                isSelected: index == _selected,
                onTap: () => setState(() => _selected = index),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            // The active group's own pastel, so the strip and the Categories
            // tab colour a group the same way. Inset and rounded, so the panel
            // reads as one block belonging to the selected pill.
            decoration: BoxDecoration(
              color: active.panelTint,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Column(
              children: [
                // Two columns on narrow phones so each card — and its
                // thumbnail — has real room, three once there is width for it.
                LayoutBuilder(
                  builder: (context, constraints) => GridView.count(
                    crossAxisCount:
                        constraints.maxWidth >= CategoryPanel.threeColumnWidth
                        ? 3
                        : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: CategoryCard.aspectRatio,
                    children: [
                      for (final item in active.items)
                        CategoryCard(
                          item: item,
                          // The panel's own pastel, so the block reads as one
                          // flat wash of colour rather than white tiles on a
                          // tint...
                          background: active.panelTint,
                          // ...with a white ring drawn back in so each product
                          // still reads as its own card within that wash.
                          borderColor: AppColors.white,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CategoryListingScreen(
                                group: active,
                                initial: item,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  // Opens the group's listing on its "All" tab — no initial
                  // sub-category — since this link stands for the whole group,
                  // not any one card above it.
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CategoryListingScreen(group: active),
                    ),
                  ),
                  child: Text(
                    '${active.viewAllLabel}  »',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandBlue,
                    ),
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

/// A group on the scrolling rail: artwork over a caption, in a card that
/// carries the brand outline while selected.
class _CategoryPill extends StatelessWidget {
  final CategoryGroup group;
  final bool isSelected;
  final VoidCallback onTap;

  static const double width = 92;

  const _CategoryPill({
    required this.group,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        // The group's own pastel, the same fill whether the chip is selected
        // or not: selecting it must not recolour it. The blue outline and bold
        // label are what mark it as chosen, and this is also the panel's fill,
        // so the active chip runs straight into the panel below it.
        color: group.panelTint,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.brandBlue : AppColors.transparent,
                width: 1.6,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 54,
                  child: AppImage(
                    image: group.image,
                    fallbackIcon: group.icon,
                    iconSize: 30,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 8),
                // Fixed height for two lines: captions run one or two lines
                // and the artwork must stay on a common baseline across the
                // rail regardless.
                SizedBox(
                  height: 32,
                  child: Text(
                    group.tabLabel,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.25,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.brandBlue
                          : AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
