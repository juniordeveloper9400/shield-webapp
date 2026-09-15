import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../location/location_sheet.dart';
import 'lab_cart_badge.dart';
import 'lab_package.dart';
import 'package_card.dart';

/// Lab landing: sample-collection location, search, the Top Packages strip,
/// booking shortcuts, the running coupon, and individually bookable profiles.
class LabTestScreen extends StatefulWidget {
  /// Opens the Top Packages sub-tab.
  final VoidCallback? onSeeAllPackages;

  const LabTestScreen({super.key, this.onSeeAllPackages});

  @override
  State<LabTestScreen> createState() => _LabTestScreenState();
}

class _LabTestScreenState extends State<LabTestScreen> {
  String? _pincode;

  Future<void> _chooseLocation() async {
    final chosen = await LocationSheet.show(context, _pincode ?? '');
    if (chosen != null && mounted) {
      setState(() => _pincode = chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 14),
            _SectionHeading(
              title: 'Top Packages',
              actionLabel: 'See all ›',
              onAction: widget.onSeeAllPackages,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 470,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: LabCatalogue.topPackages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: 330,
                  child: PackageCard(
                    package: LabCatalogue.topPackages[index],
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
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _CouponBanner(),
            ),
            const SizedBox(height: 20),
            const _SectionHeading(
              title: 'Top Profiles and Tests',
              actionLabel: 'See all ›',
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    for (
                      var i = 0;
                      i < LabCatalogue.topProfiles.length;
                      i++
                    ) ...[
                      _ProfileTile(profile: LabCatalogue.topProfiles[i]),
                      if (i != LabCatalogue.topProfiles.length - 1)
                        const Divider(height: 1, color: AppColors.border),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
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

class _ProfileTile extends StatelessWidget {
  final LabProfile profile;

  const _ProfileTile({required this.profile});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Text(profile.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${profile.parameters} parameters',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
