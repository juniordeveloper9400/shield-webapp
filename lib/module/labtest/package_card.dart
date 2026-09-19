import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'lab_package.dart';
import 'lab_package_screen.dart';

/// Full diagnostic-package card: badge, headline stats, profile breakdown,
/// and the price/book footer.
///
/// Used both in the horizontal "Top Packages" strip and in the full-page list,
/// so the two can never drift apart.
class PackageCard extends StatelessWidget {
  final LabPackage package;
  final VoidCallback? onViewAll;

  /// Set inside the fixed-height horizontal strip, where cards of differing
  /// content must share one height. The breakdown area then absorbs the slack
  /// and scrolls if it runs short, keeping the price footer pinned rather than
  /// letting a tall package overflow its box.
  final bool fillHeight;

  const PackageCard({
    super.key,
    required this.package,
    this.onViewAll,
    this.fillHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: _Headline(package: package),
          ),
          _ProfileStrip(package: package, onViewAll: onViewAll),
          if (fillHeight)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: package.inheritsFrom == null
                    ? _ProfileGrid(profiles: package.profiles)
                    : _InheritedBlock(package: package),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: package.inheritsFrom == null
                  ? _ProfileGrid(profiles: package.profiles)
                  : _InheritedBlock(package: package),
            ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _PriceRow(package: package),
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  final LabPackage package;

  const _Headline({required this.package});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: AppColors.brandBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${package.testCount}',
                style: const TextStyle(
                  fontSize: 25,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'TESTS',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC9D8F0),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                package.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Stat(
                    icon: Icons.star_rounded,
                    colour: const Color(0xFFF5A623),
                    text: package.rating,
                    bold: true,
                  ),
                  _Stat(
                    icon: Icons.person_rounded,
                    colour: AppColors.brandBlue,
                    text: package.booked,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Stat(
                    icon: Icons.home_outlined,
                    colour: AppColors.brandGreenDeep,
                    text: 'Free collection',
                  ),
                  _Stat(
                    icon: Icons.description_outlined,
                    colour: AppColors.brandBlue,
                    text: package.reportIn,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color colour;
  final String text;
  final bool bold;

  const _Stat({
    required this.icon,
    required this.colour,
    required this.text,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colour),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: AppColors.textBody,
          ),
        ),
      ],
    );
  }
}

class _ProfileStrip extends StatelessWidget {
  final LabPackage package;
  final VoidCallback? onViewAll;

  const _ProfileStrip({required this.package, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.pageTint,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${package.testCount} tests · ${package.profileCount} profiles',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'View all',
              style: TextStyle(
                fontSize: 14,
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

class _ProfileGrid extends StatelessWidget {
  final List<LabProfile> profiles;

  const _ProfileGrid({required this.profiles});

  @override
  Widget build(BuildContext context) {
    // Two columns, filling left-to-right like the reference.
    return Column(
      children: [
        for (var i = 0; i < profiles.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _ProfileRow(profile: profiles[i])),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < profiles.length
                      ? _ProfileRow(profile: profiles[i + 1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final LabProfile profile;

  const _ProfileRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(profile.emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textDark,
            ),
          ),
        ),
        if (profile.parameters > 0) ...[
          const SizedBox(width: 6),
          Text(
            '${profile.parameters}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _InheritedBlock extends StatelessWidget {
  final LabPackage package;

  const _InheritedBlock({required this.package});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.offerTint,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 19,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.inheritsFrom!,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandBlue,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      package.inheritsSummary ?? '',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (package.extrasLabel != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.border)),
              // Flexible so the label yields before the row overflows; the
              // dividers alone cannot absorb an over-wide caption.
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    package.extrasLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: AppColors.brandGreenDeep,
                    ),
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AppColors.border)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (final extra in package.extras)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ProfileRow(profile: extra),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  final LabPackage package;

  const _PriceRow({required this.package});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '₹${package.price}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    '₹${package.mrp}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                package.savedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandGreenDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          // Books nothing directly: the patient count has to be chosen, and
          // the detail screen is where that decision is made.
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LabPackageScreen(package: package),
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandBlue,
            side: const BorderSide(color: AppColors.brandBlue),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Book',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
