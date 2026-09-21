import 'package:flutter/material.dart';

import '../../data/backend/care_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import '../location/location_sheet.dart';
import 'lab_cart_badge.dart';
import 'lab_package.dart';
import 'package_card.dart';
import 'top_packages_screen.dart';

/// The strip shows the first [_topPackageCount] packages in the admin's own
/// sort order — the whole point of setting `sort` on `app.lab_package` is to
/// choose what leads here, so this reads directly off it rather than a
/// separate "is this one featured" flag the schema doesn't have.
const int _topPackageCount = 5;

/// Lab landing: sample-collection location, search, the Top Packages strip,
/// booking shortcuts, and the running coupon.
class LabTestScreen extends StatefulWidget {
  /// Opens the Top Packages sub-tab.
  final VoidCallback? onSeeAllPackages;

  const LabTestScreen({super.key, this.onSeeAllPackages});

  @override
  State<LabTestScreen> createState() => _LabTestScreenState();
}

class _LabTestScreenState extends State<LabTestScreen> {
  String? _pincode;
  List<LabPackage>? _packages;
  List<LabCategory>? _categories;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      CareRepository.instance.fetchLabPackages(),
      CareRepository.instance.fetchLabCategories(),
    ]);
    if (mounted) {
      // null means "unconfigured or unreachable", same as "nothing to show"
      // as far as this screen is concerned — without the fallback, a build
      // with no database configured (or offline) would spin forever instead
      // of settling on the empty state.
      setState(() {
        _packages = results[0] as List<LabPackage>? ?? const [];
        _categories = results[1] as List<LabCategory>? ?? const [];
      });
    }
  }

  void _openCategory(LabCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TopPackagesScreen(category: category)),
    );
  }

  Future<void> _chooseLocation() async {
    final chosen = await LocationSheet.show(context, _pincode ?? '');
    if (chosen != null && mounted) {
      setState(() => _pincode = chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = _packages;
    final topPackages = packages == null
        ? const <LabPackage>[]
        : packages.take(_topPackageCount).toList();
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 16),
              child: Column(
                children: [
                  _CollectionHeader(pincode: _pincode, onTap: _chooseLocation),
                  const SizedBox(height: 14),
                  const _LabSearchField(),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_categories == null || _categories!.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Explore by health concern',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _CategoryGrid(
                  categories: _categories,
                  onTap: _openCategory,
                ),
              ),
              const SizedBox(height: 18),
            ],
            _SectionHeading(
              title: 'Top Packages',
              actionLabel: 'See all ›',
              onAction: widget.onSeeAllPackages,
            ),
            const SizedBox(height: 10),
            if (packages == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (topPackages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: _NoPackages(),
              )
            else
              SizedBox(
                height: 470,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: topPackages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => SizedBox(
                    width: 330,
                    child: PackageCard(
                      package: topPackages[index],
                      onViewAll: widget.onSeeAllPackages,
                      fillHeight: true,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _BookingShortcuts(),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _CouponBanner(),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Explore by health concern": a 4-across grid of category tiles. Kept as
/// one boxed card (loading spinner while [categories] is null) rather than
/// bare tiles on the page background, the same framing [_NoPackages] and the
/// booking shortcuts use elsewhere on this screen.
class _CategoryGrid extends StatelessWidget {
  final List<LabCategory>? categories;
  final ValueChanged<LabCategory> onTap;

  const _CategoryGrid({required this.categories, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = categories;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      child: items == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          : GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Taller than the icon+two lines of text strictly need, so a
              // longer category name, a wider system font, or a larger text
              // scale never overflows the cell.
              childAspectRatio: 0.66,
              children: [
                for (final category in items)
                  _CategoryTile(
                    category: category,
                    onTap: () => onTap(category),
                  ),
              ],
            ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final LabCategory category;
  final VoidCallback onTap;

  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.pageTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AppImage(
                image: category.image,
                fallbackIcon: Icons.science_outlined,
                iconSize: 24,
                iconColor: AppColors.brandBlue,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${category.testCount} test${category.testCount == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPackages extends StatelessWidget {
  const _NoPackages();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: const Column(
        children: [
          Icon(Icons.science_outlined, size: 34, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text(
            'No packages available right now',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  final String? pincode;
  final VoidCallback onTap;

  const _CollectionHeader({required this.pincode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final chosen = pincode;

    return Row(
      children: [
        const Icon(
          Icons.location_on_outlined,
          size: 26,
          color: AppColors.brandBlue,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Collect sample from',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        chosen == null
                            ? 'Select location'
                            : LocationSheet.describe(chosen),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.textDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // The lab section keeps its own basket, so this is never the medicine
        // cart's badge.
        const LabCartBadge(),
      ],
    );
  }
}

class _LabSearchField extends StatelessWidget {
  const _LabSearchField();

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search for CBC',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15.5),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textMuted,
          size: 22,
        ),
        filled: true,
        fillColor: AppColors.pageTint,
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.4),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  const _SectionHeading({
    required this.title,
    required this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppColors.brandBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingShortcuts extends StatelessWidget {
  const _BookingShortcuts();

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ShortcutTile(
              icon: Icons.phone_in_talk_outlined,
              tint: AppColors.offerTint,
              iconColour: AppColors.brandBlue,
              top: 'Book via',
              bottom: 'Call',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ShortcutTile(
              icon: Icons.chat_bubble_outline_rounded,
              tint: AppColors.greenTint,
              iconColour: AppColors.brandGreenDeep,
              top: 'Book via',
              bottom: 'WhatsApp',
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color iconColour;
  final String top;
  final String bottom;

  const _ShortcutTile({
    required this.icon,
    required this.tint,
    required this.iconColour,
    required this.top,
    required this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 21, color: iconColour),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      top,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      bottom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CouponBanner extends StatelessWidget {
  const _CouponBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.offerTint,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.local_offer_outlined,
              size: 20,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AVAILABLE COUPON',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Flat 25% off on all tests',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandBlue,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Applicable on all bookings above ₹700',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textBody),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
