
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart' show FaIcon, FontAwesomeIcons;

import '../../data/backend/care_repository.dart';
import '../../data/backend/contact_repository.dart';
import '../../money.dart';
import '../../phone.dart';
import '../../theme/app_colors.dart';
import '../home/prescription_card.dart' show PrescriptionCard;
import 'dietitian.dart';

/// The Dietitian destination: who you can talk to, and what it costs.
class DietitianScreen extends StatefulWidget {
  const DietitianScreen({super.key});

  @override
  State<DietitianScreen> createState() => _DietitianScreenState();
}

class _DietitianScreenState extends State<DietitianScreen> {
  String _query = '';
  List<Dietitian>? _dietitians;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dietitians = await CareRepository.instance.fetchDietitians();
    if (mounted) {
      // null means "unconfigured or unreachable", treated the same as
      // "nothing to show" — see LabTestScreen's identical fallback.
      setState(() => _dietitians = dietitians ?? const []);
    }
  }

  /// Opens a WhatsApp chat with the admin desk (the order line until one is
  /// set), with the question already typed in.
  Future<void> _openWhatsApp() async {
    final admin = await ContactRepository.instance.adminWhatsapp();
    if (!mounted) return;
    await WhatsApp.open(
      context,
      admin ?? PrescriptionCard.orderPhone,
      message: 'Hi, I would like to talk to a dietitian.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final dietitians = _dietitians;
    final results = dietitians == null
        ? null
        : DietitianDirectory.search(dietitians, _query);

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Dietitian',
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
      floatingActionButton: FloatingActionButton(
        tooltip: 'Chat with a dietitian on WhatsApp',
        backgroundColor: AppColors.brandGreenDeep,
        foregroundColor: AppColors.white,
        onPressed: _openWhatsApp,
        child: const FaIcon(FontAwesomeIcons.whatsapp, size: 30),
      ),
      body: ListView(
        // Clears the floating WhatsApp button at the bottom right.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const _ProgramBanner(),
          const SizedBox(height: 16),
          const _ServicesSection(),
          const SizedBox(height: 16),
          _SearchField(onChanged: (value) => setState(() => _query = value)),
          const SizedBox(height: 16),
          if (results == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (results.isEmpty)
            _NoMatches(hasQuery: _query.trim().isNotEmpty)
          else
            for (final dietitian in results) ...[
              _DietitianCard(dietitian: dietitian),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

/// The CHANGE programme banner, shown at the top of the screen.
class _ProgramBanner extends StatelessWidget {
  const _ProgramBanner();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.asset(
        'assets/dietitian/change_program.png',
        width: double.infinity,
        fit: BoxFit.cover,
        semanticLabel: 'CHANGE nutrition and lifestyle programme',
      ),
    );
  }
}

/// The diet services, as the clinic's own printed panels: the CHANGE MAX
/// programme, personalised consultation, the diet kit, exercises and discounts,
/// and pharmacy and home-care support.
class _ServicesSection extends StatelessWidget {
  const _ServicesSection();

  static const _panels = [
    _ServicePanel('assets/dietitian/change_max.png', 'CHANGE MAX diet and nutrition guidance'),
    _ServicePanel('assets/dietitian/services_1.png', 'Personalised diet consultation and monthly diet chart'),
    _ServicePanel('assets/dietitian/services_2.png', 'Diet kit and weekly progress check'),
    _ServicePanel('assets/dietitian/services_3.png', 'Customised exercises and diagnostic test discounts'),
    _ServicePanel('assets/dietitian/services_4.png', 'Supplement discounts, pharmacy support and home care'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final panel in _panels) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              panel.asset,
              fit: BoxFit.fitWidth,
              semanticLabel: panel.label,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ServicePanel {
  const _ServicePanel(this.asset, this.label);

  final String asset;
  final String label;
}

class _SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _SearchField({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search by name or condition',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.brandBlue,
          size: 22,
        ),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.searchBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.6),
        ),
      ),
    );
  }
}

class _DietitianCard extends StatelessWidget {
  final Dietitian dietitian;

  const _DietitianCard({required this.dietitian});

  void _book(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Consultation with ${dietitian.name} requested · '
            '${dietitian.nextSlot}',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.pageTint,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  dietitian.initials,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dietitian.name,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dietitian.qualification,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppColors.textBody,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dietitian.summary,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final area in dietitian.focus)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.pageTint,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    area,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          // Wrap, not Row: the fee, the slot and the button do not fit one
          // line at 320px.
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '₹${formatRupees(dietitian.fee)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: AppColors.brandGreenDeep,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dietitian.nextSlot,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandGreenDark,
                    ),
                  ),
                ],
              ),
              FilledButton(
                onPressed: () => _book(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Book',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  /// Whether this is "nothing matched the search" (a condition to try
  /// instead makes sense) or "there is no panel to search yet" (it doesn't).
  final bool hasQuery;

  const _NoMatches({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      child: Column(
        children: [
          const Icon(
            Icons.person_search_outlined,
            size: 38,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 10),
          Text(
            hasQuery
                ? 'No dietitian matches that'
                : 'No dietitians available right now',
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          if (hasQuery) ...[
            const SizedBox(height: 4),
            const Text(
              'Try a condition instead, such as diabetes or thyroid.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
