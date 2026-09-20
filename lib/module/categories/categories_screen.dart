import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'category_card.dart';
import 'category_catalogue.dart';
import 'category_listing_screen.dart';

/// Full category browser reached from the Categories tab.
///
/// One tinted panel per group, each closed by its own "View all …" link —
/// the same card and the same catalogue the home strip draws from, so the two
/// surfaces cannot drift apart.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  @override
  void initState() {
    super.initState();
    // The backend copy can still be loading (main.dart's ensureLoaded) the
    // moment this screen opens — ask once here and rebuild if it lands later.
    CategoryCatalog.instance.addListener(_onCatalogChanged);
    CategoryCatalog.instance.ensureLoaded();
  }

  @override
  void dispose() {
    CategoryCatalog.instance.removeListener(_onCatalogChanged);
    super.dispose();
  }

  void _onCatalogChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        // Always a pushed route now, never a tab — so it keeps its back button.
        title: const Text(
          'Categories',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          for (final group in CategoryCatalogue.groups) ...[
            Text(
              group.title,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            CategoryPanel(
              group: group,
              onSelect: (item) => _openListing(context, group, item),
              onViewAll: () => _openListing(context, group, null),
            ),
            const SizedBox(height: 26),
          ],
        ],
      ),
    );
  }

  /// There is no catalogue listing behind a category yet, so a tap says where
  /// it would go rather than silently doing nothing.
  /// Opens the group's listing, on [item] when one was tapped and on the
  /// "All" chip when the group heading's view-all link was used.
  static void _openListing(
    BuildContext context,
    CategoryGroup group,
    SubCategory? item,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryListingScreen(group: group, initial: item),
      ),
    );
  }
}
