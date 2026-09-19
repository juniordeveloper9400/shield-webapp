import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'lab_cart_badge.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';
import 'patient_count_sheet.dart';

/// Package detail — what "Book" opens.
///
/// Header, the four facts a patient needs before booking, the organs covered,
/// the price with Add, the running coupon, and the description.
class LabPackageScreen extends StatelessWidget {
  final LabPackage package;

  const LabPackageScreen({super.key, required this.package});

  /// Chips shown before "View more" folds the rest away.
  static const int visibleOrgans = 6;

  Future<void> _add(BuildContext context) async {
    final cart = LabCartService.instance;
    final chosen = await PatientCountSheet.show(
      context,
      package,
      initial: cart.patientsFor(package),
    );
    if (chosen == null || !context.mounted) {
      return;
    }

    cart.book(package, patients: chosen);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            chosen == 1
                ? '${package.name} added for 1 patient'
                : '${package.name} added for $chosen patients',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Product Details',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search_rounded),
            color: AppColors.textDark,
            tooltip: 'Search packages',
          ),
          const Padding(
            padding: EdgeInsets.only(right: 10, left: 2),
            child: Center(child: LabCartBadge()),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(package: package),
          const SizedBox(height: 10),
          _FactStrip(package: package),
          const SizedBox(height: 10),
          if (package.organs.isNotEmpty) ...[
            _OrgansBlock(package: package),
            const SizedBox(height: 10),
          ],
          _PriceBlock(package: package, onAdd: () => _add(context)),
          const SizedBox(height: 10),
          const _CouponCard(),
          const SizedBox(height: 10),
          _AboutBlock(package: package),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final LabPackage package;

  const _Header({required this.package});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The reference shows a lifestyle photograph here. There is no
              // artwork for the packages in this project, so the tile carries
              // the section's own mark rather than a stand-in photo.
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: AppColors.offerTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.biotech_outlined,
                  size: 36,
                  color: AppColors.brandBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'SHIELD ${package.name} Package',
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetaChip(icon: Icons.person_rounded, label: package.forWhom),
              _MetaChip(icon: Icons.cake_outlined, label: package.ageRange),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: AppColors.textBody),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }
}

/// The four facts a patient needs before booking.
class _FactStrip extends StatelessWidget {
  final LabPackage package;

  const _FactStrip({required this.package});

  @override
  Widget build(BuildContext context) {
    final facts = [
      _Fact(Icons.biotech_outlined, 'CONTAINS', '${package.testCount} Tests'),
      _Fact(Icons.restaurant_outlined, 'PREPARATION', package.preparation),
      _Fact(Icons.science_outlined, 'SAMPLE', package.sample),
      _Fact(Icons.description_outlined, 'REPORT IN', package.reportIn),
    ];

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      // Scrolls sideways rather than wrapping: four tiles do not fit at 320px,
      // and a 2×2 grid would break the strip the reference reads as one row.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final fact in facts) ...[
              _FactTile(fact: fact),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact {
  final IconData icon;
  final String label;
  final String value;

  const _Fact(this.icon, this.label, this.value);
}

class _FactTile extends StatelessWidget {
  final _Fact fact;

  const _FactTile({required this.fact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fact.icon, size: 24, color: AppColors.textBody),
          const SizedBox(height: 12),
          Text(
            fact.label,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            fact.value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrgansBlock extends StatefulWidget {
  final LabPackage package;

  const _OrgansBlock({required this.package});

  @override
  State<_OrgansBlock> createState() => _OrgansBlockState();
}

class _OrgansBlockState extends State<_OrgansBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final organs = widget.package.organs;
    final hasMore = organs.length > LabPackageScreen.visibleOrgans;
    final shown = _expanded || !hasMore
        ? organs
        : organs.take(LabPackageScreen.visibleOrgans).toList();

    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ORGANS & SYSTEMS COVERED',
            style: TextStyle(
              fontSize: 12.5,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final organ in shown) _OrganChip(label: organ)],
          ),
          if (hasMore) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _expanded ? 'View less ‹' : 'View more ›',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrganChip extends StatelessWidget {
  final String label;

  const _OrganChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textDark,
        ),
      ),
    );
  }
}

class _PriceBlock extends StatelessWidget {
  final LabPackage package;
  final VoidCallback onAdd;

  const _PriceBlock({required this.package, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '₹${package.price}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '₹${package.mrp}',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textMuted,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              if (package.discountLabel.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.greenTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    package.discountLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandGreenDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Reflects the basket, so reopening a booked package offers to
          // change the count rather than pretending nothing is booked.
          ListenableBuilder(
            listenable: LabCartService.instance,
            builder: (context, _) {
              final patients = LabCartService.instance.patientsFor(package);

              return SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onAdd,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: const BorderSide(color: AppColors.searchBorder),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    patients == null
                        ? 'Add'
                        : patients == 1
                        ? 'Booked for 1 patient · Change'
                        : 'Booked for $patients patients · Change',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
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
                borderRadius: BorderRadius.circular(10),
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
                      fontSize: 11,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Flat 25% off on all tests',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Applicable on all bookings above ₹700',
                    style: TextStyle(fontSize: 13, color: AppColors.textBody),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutBlock extends StatelessWidget {
  final LabPackage package;

  const _AboutBlock({required this.package});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About this Package',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            package.about.isEmpty ? package.name : package.about,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textBody,
            ),
          ),
        ],
      ),
    );
  }
}
