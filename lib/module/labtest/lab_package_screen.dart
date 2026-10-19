import 'package:flutter/material.dart';

import '../../data/backend/contact_repository.dart';
import '../../phone.dart';
import '../../theme/app_colors.dart';
import '../home/prescription_card.dart' show PrescriptionCard;
import 'lab_cart_badge.dart';
import 'lab_cart_screen.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';
import '../registration/registration_gate.dart';
import 'lab_patient_picker_sheet.dart';
import 'lab_test_detail_screen.dart';

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
    // Booking a lab test is an action — registered members only.
    if (!await RegistrationGate.ensure(context, action: 'book lab tests')) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final cart = LabCartService.instance;
    final chosen = await LabPatientPickerSheet.show(
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
            chosen.length == 1
                ? '${package.name} added for 1 patient'
                : '${package.name} added for ${chosen.length} patients',
          ),
        ),
      );
  }

  /// Opens a WhatsApp chat with the admin desk, the same "ask before you
  /// book" line every other screen's WhatsApp shortcut reaches.
  Future<void> _openWhatsApp(BuildContext context) async {
    final admin = await ContactRepository.instance.adminWhatsapp();
    if (!context.mounted) return;
    await WhatsApp.open(
      context,
      admin ?? PrescriptionCard.orderPhone,
      message: 'Hi, I have a question about ${package.name}.',
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
      // Always reachable while browsing a test's details, wherever the
      // member has scrolled to — the same "ask before you book" shortcut
      // every other booking screen offers, just pinned here instead of
      // sitting inline in one section.
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('package-whatsapp-fab'),
        onPressed: () => _openWhatsApp(context),
        backgroundColor: AppColors.brandGreenDeep,
        tooltip: 'Chat on WhatsApp',
        child: const Icon(Icons.chat_rounded, color: AppColors.white),
      ),
      bottomNavigationBar: _BottomBar(package: package, onAdd: () => _add(context)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _TopCard(package: package),
          const SizedBox(height: 10),
          if (package.organs.isNotEmpty) ...[
            _OrgansBlock(package: package),
            const SizedBox(height: 10),
          ],
          _AboutBlock(package: package),
          if (package.whyThisTest.isNotEmpty) ...[
            const SizedBox(height: 10),
            _DetailTextBlock(
              title: 'Why this test',
              body: package.whyThisTest,
            ),
          ],
          if (package.symptoms.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SymptomsBlock(symptoms: package.symptoms),
          ],
          if (package.profiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            _IncludedTestsBlock(profiles: package.profiles),
          ],
          if (package.fasting.isNotEmpty || package.preparation.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PreparationBlock(package: package),
          ],
          const SizedBox(height: 10),
          _HowItWorksBlock(package: package),
          const SizedBox(height: 10),
          _CommonQuestionsBlock(package: package),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The fixed footer every scroll position keeps in view: how many patients
/// this test is booked for (tap to choose or change), and — once the basket
/// holds at least one booking — the running total with a shortcut straight
/// to the cart.
///
/// Two distinct layouts, not one bar with parts disabled: before this
/// package has been added, there is nothing to pick a patient count for yet,
/// so the bar is just the price and a plain "Add" button — the same shape
/// every other product-style price footer in the app uses. Only once it is
/// actually in the basket does the bar switch to the patient count (tap to
/// change it) and a "View Cart" button.
class _BottomBar extends StatelessWidget {
  final LabPackage package;
  final VoidCallback onAdd;

  const _BottomBar({required this.package, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LabCartService.instance,
      builder: (context, _) {
        final cart = LabCartService.instance;
        final patients = cart.patientsFor(package);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: patients == null
                ? _NotAddedBar(package: package, onAdd: onAdd)
                : _AddedBar(
                    package: package,
                    patients: patients.length,
                    cart: cart,
                    onChangePatients: onAdd,
                  ),
          ),
        );
      },
    );
  }
}

/// Not yet booked: the package's own price, and a plain "Add" button that
/// opens the patient picker.
class _NotAddedBar extends StatelessWidget {
  final LabPackage package;
  final VoidCallback onAdd;

  const _NotAddedBar({required this.package, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                '₹${package.price}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                '₹${package.mrp}',
                style: const TextStyle(
                  fontSize: 13.5,
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
                    horizontal: 7,
                    vertical: 3,
                  ),
                  child: Text(
                    package.discountLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandGreenDark,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: ElevatedButton(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: const Text(
              'Add',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

/// Already booked: how many patients (tap to change), and the running
/// basket total with a shortcut straight to the cart.
class _AddedBar extends StatelessWidget {
  final LabPackage package;
  final int patients;
  final LabCartService cart;
  final VoidCallback onChangePatients;

  const _AddedBar({
    required this.package,
    required this.patients,
    required this.cart,
    required this.onChangePatients,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onChangePatients,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandBlue,
              side: const BorderSide(color: AppColors.searchBorder),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: Text(
              patients == 1 ? '1 Patient' : '$patients Patients',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LabCartScreen())),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₹${cart.payable} · ${cart.bookingCount} ${cart.bookingCount == 1 ? 'Item' : 'Items'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFC9D8F0),
                  ),
                ),
                const Text(
                  'View Cart',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The package name, the facts a patient needs before booking, and the
/// price — one tinted card instead of three separate white sections, so the
/// whole "what is this and what does it cost" picture reads as a single
/// unit at the top of the page.
class _TopCard extends StatelessWidget {
  final LabPackage package;

  const _TopCard({required this.package});

  @override
  Widget build(BuildContext context) {
    final effectiveReportOn = package.reportOn.isNotEmpty
        ? package.reportOn
        : package.reportIn;
    final facts = [
      if (package.sample.isNotEmpty)
        _Fact(Icons.science_outlined, 'SAMPLE', package.sample),
      if (effectiveReportOn.isNotEmpty)
        _Fact(Icons.schedule_outlined, 'REPORT ON', effectiveReportOn),
      if (package.testMode.isNotEmpty)
        _Fact(Icons.biotech_outlined, 'TEST MODE', package.testMode),
      if (package.fasting.isNotEmpty)
        _Fact(Icons.no_food_outlined, 'FASTING', package.fasting),
    ];

    return Container(
      width: double.infinity,
      // White on either side of the tinted card below — the scaffold's own
      // pageTint would otherwise show through there and read as more of the
      // same blue wash rather than a clear gutter around it.
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.panelBlue,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The reference shows a lifestyle photograph here. There is
                // no artwork for the packages in this project, so the tile
                // carries the section's own mark rather than a stand-in
                // photo.
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: AppColors.white,
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
                      'Sahakar 360 ${package.name} Package',
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
            if (package.shortName.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Also referred as',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final alias in package.shortName.split(','))
                    if (alias.trim().isNotEmpty)
                      _AliasChip(label: alias.trim()),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // One compact row — the tiles share the card's width instead of
            // wrapping onto a second line.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(child: _FactTile(fact: facts[i])),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
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
          ],
        ),
      ),
    );
  }
}

class _AliasChip extends StatelessWidget {
  final String label;

  const _AliasChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
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

/// One fact inside [_TopCard] — white against that card's own tint, the
/// same "card within a card" contrast the reference uses.
class _FactTile extends StatelessWidget {
  final _Fact fact;

  const _FactTile({required this.fact});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fact.icon, size: 18, color: AppColors.textBody),
          const SizedBox(height: 6),
          Text(
            fact.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            fact.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
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

/// "Included In The Package" — each included test's alias and name, with a
/// chevron that opens its own full detail page when it carries a real
/// [LabProfile.testId] (migration 0106).
class _IncludedTestsBlock extends StatelessWidget {
  final List<LabProfile> profiles;

  const _IncludedTestsBlock({required this.profiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Includes these tests',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.offerTint,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(7),
                child: Text(
                  '${profiles.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final profile in profiles) _IncludedTestRow(profile: profile),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL',
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                  ),
                ),
                Text(
                  '${profiles.length} test${profiles.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
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

class _IncludedTestRow extends StatelessWidget {
  final LabProfile profile;

  const _IncludedTestRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    final tappable = profile.testId != null;
    final displayName = profile.shortName.isNotEmpty
        ? '${profile.name} (${profile.shortName})'
        : profile.name;

    return InkWell(
      onTap: tappable
          ? () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LabTestDetailScreen(testId: profile.testId!),
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.offerTint,
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              child: Text(
                profile.parameters > 1
                    ? '${profile.parameters} TESTS'
                    : '1 TEST',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayName,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ),
            if (tappable)
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

/// A plain title + body text block — "Why this test" (`package.
/// whyThisTest`), staff-entered on the Test Master's "Why this test" tab.
class _DetailTextBlock extends StatelessWidget {
  final String title;
  final String body;

  const _DetailTextBlock({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
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

/// "Symptoms that may indicate this test" — chips entered on the Test
/// Master's "Why this test" tab, never hardcoded here.
class _SymptomsBlock extends StatelessWidget {
  final List<String> symptoms;

  const _SymptomsBlock({required this.symptoms});

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
            'Symptoms that may indicate this test',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final symptom in symptoms) _OrganChip(label: symptom),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Preparation instructions" — built from [LabPackage.fasting] (the
/// Test Master's own Fasting field) and the free-text [LabPackage.preparation]
/// sentence, when either is set. Nothing here is hardcoded: a package with
/// neither simply never shows this block (see the caller's own guard).
class _PreparationBlock extends StatelessWidget {
  final LabPackage package;

  const _PreparationBlock({required this.package});

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
            'Preparation instructions',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          if (package.fasting.isNotEmpty) _PreparationLine(package.fasting),
          if (package.preparation.isNotEmpty)
            _PreparationLine(package.preparation),
        ],
      ),
    );
  }
}

class _PreparationLine extends StatelessWidget {
  final String text;

  const _PreparationLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(
              Icons.circle,
              size: 6,
              color: AppColors.textMuted,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "How It Works" — the three-step booking flow every lab test follows here
/// (book a slot, sample collection, report). [package.reportIn] is the only
/// test-specific fact; the steps themselves describe the one booking flow
/// the app offers, the same for every test, so they are fixed copy rather
/// than something each Test Master row would need to repeat.
class _HowItWorksBlock extends StatelessWidget {
  final LabPackage package;

  const _HowItWorksBlock({required this.package});

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        'Book a slot',
        'Pick a convenient time window, any day of the week.',
      ),
      (
        'Sample taken at home',
        'A trained phlebotomist collects your sample at your door.',
      ),
      (
        'Report ${package.reportIn.isEmpty ? 'ready soon' : 'in ${package.reportIn}'}',
        'Your digital report is shared on WhatsApp and in the app.',
      ),
    ];

    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How It Works',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            _HowItWorksStep(
              number: i + 1,
              title: steps[i].$1,
              body: steps[i].$2,
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  final bool isLast;

  const _HowItWorksStep({
    required this.number,
    required this.title,
    required this.body,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.brandBlue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1.5, color: AppColors.border),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: AppColors.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Common Questions" — the questions a member asks before booking any test
/// here, the same across every one; only the answers that genuinely vary
/// (the fasting window) read from [package] rather than being fixed copy.
class _CommonQuestionsBlock extends StatelessWidget {
  final LabPackage package;

  const _CommonQuestionsBlock({required this.package});

  @override
  Widget build(BuildContext context) {
    final questions = <(String, String)>[
      (
        "Do I need a doctor's prescription to book this?",
        'No. You can book this test directly — no prescription or consultation needed.',
      ),
      (
        'Is ₹${package.price} the final amount, or do I pay at collection?',
        '₹${package.price} is the full price — nothing further is collected at your door.',
      ),
      if (package.fasting.isNotEmpty)
        (
          'What time should I stop eating?',
          'Fast for ${package.fasting} before your sample is taken — plain water is fine.',
        ),
      (
        'Can I book this for my parents at a different address?',
        'Yes — add each person as their own patient and set a separate collection address for them at checkout.',
      ),
      (
        'Is home collection available at my pincode?',
        "You'll be asked to confirm your address and a convenient time slot when booking — if it isn't serviceable there, you'll see that before you pay.",
      ),
      (
        'What if a value comes back out of range?',
        "It's flagged clearly in your report, and our team can help you understand next steps.",
      ),
    ];

    return Container(
      width: double.infinity,
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Common Questions',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          for (final q in questions)
            _QuestionTile(question: q.$1, answer: q.$2),
        ],
      ),
    );
  }
}

class _QuestionTile extends StatefulWidget {
  final String question;
  final String answer;

  const _QuestionTile({required this.question, required this.answer});

  @override
  State<_QuestionTile> createState() => _QuestionTileState();
}

class _QuestionTileState extends State<_QuestionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.question,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              widget.answer,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textBody,
              ),
            ),
          ),
        const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}
