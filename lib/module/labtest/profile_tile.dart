import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';
import 'lab_package_screen.dart';
import 'patient_count_sheet.dart';

/// "Top Profiles and Tests": a card of single tests and group tests — the ones
/// the lab switched on with "Show in the app" on the console's Test Master —
/// each a row with its price, what it saves and a "+" to book it.
///
/// [profiles] is shown in full; the caller decides how many to hand it. [images]
/// maps a category id to that category's icon, so a listed test wears the icon
/// of the health concern it is filed under. [footer], when given, sits under
/// the last row ("View all 10 tests ›").
class LabProfileList extends StatelessWidget {
  final List<LabPackage> profiles;
  final Map<String, String> images;
  final Widget? footer;

  const LabProfileList({
    super.key,
    required this.profiles,
    this.images = const {},
    this.footer,
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
        children: [
          for (var i = 0; i < profiles.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            LabProfileTile(
              profile: profiles[i],
              image: images[profiles[i].categoryId] ?? '',
            ),
          ],
          if (footer != null) ...[
            const Divider(height: 1, color: AppColors.border),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// One row of [LabProfileList]. Tapping the row opens the test's own page;
/// the "+" books it straight from the list, through the same
/// "select number of patients" sheet a package's Add uses.
class LabProfileTile extends StatelessWidget {
  final LabPackage profile;

  /// The icon to show — usually the category's; empty falls back to a plain
  /// lab icon.
  final String image;

  const LabProfileTile({super.key, required this.profile, this.image = ''});

  Future<void> _add(BuildContext context) async {
    final cart = LabCartService.instance;
    final chosen = await PatientCountSheet.show(
      context,
      profile,
      initial: cart.patientsFor(profile),
    );
    if (chosen != null) {
      cart.book(profile, patients: chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSaving =
        profile.mrpValue > profile.priceValue && profile.priceValue >= 0;
    final tests = profile.testCount <= 0 ? 1 : profile.testCount;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LabPackageScreen(package: profile)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.goldTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AppImage(
                image: image,
                fallbackIcon: Icons.science_outlined,
                iconSize: 24,
                iconColor: AppColors.goldAccent,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      Text(
                        '₹${profile.price}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (hasSaving) ...[
                        Text(
                          '₹${profile.mrp}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          profile.discountLabel.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandGreenDark,
                          ),
                        ),
                      ],
                      Text(
                        '· $tests test${tests == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ListenableBuilder(
              listenable: LabCartService.instance,
              builder: (context, _) {
                final inBasket =
                    LabCartService.instance.patientsFor(profile) != null;
                return Semantics(
                  button: true,
                  label: inBasket
                      ? 'Change patients for ${profile.name}'
                      : 'Add ${profile.name}',
                  child: InkWell(
                    key: ValueKey('add-profile-${profile.id}'),
                    onTap: () => _add(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: inBasket ? AppColors.greenTint : AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: inBasket
                              ? AppColors.brandGreenDark
                              : AppColors.border,
                        ),
                      ),
                      child: Icon(
                        inBasket ? Icons.check_rounded : Icons.add_rounded,
                        color: inBasket
                            ? AppColors.brandGreenDark
                            : AppColors.brandBlue,
                        size: 26,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
