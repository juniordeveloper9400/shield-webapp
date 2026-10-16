import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../patients/patient_book.dart';
import '../patients/patient_form_sheet.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';

/// Choose a count, collect one distinct saved or new patient for each slot,
/// then review the named patients and per-patient price before adding to cart.
class LabPatientPickerSheet extends StatefulWidget {
  final LabPackage package;

  /// Pre-selected when the package is already booked, so reopening the
  /// sheet starts from the same count and patients rather than from zero.
  final List<Patient>? initial;

  const LabPatientPickerSheet({super.key, required this.package, this.initial});

  /// Returns the chosen patients, or null when dismissed.
  static Future<List<Patient>?> show(
    BuildContext context,
    LabPackage package, {
    List<Patient>? initial,
  }) {
    return showModalBottomSheet<List<Patient>>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => LabPatientPickerSheet(package: package, initial: initial),
    );
  }

  @override
  State<LabPatientPickerSheet> createState() => _LabPatientPickerSheetState();
}

enum _Step { count, collecting, review }

class _LabPatientPickerSheetState extends State<LabPatientPickerSheet> {
  late _Step _step = (widget.initial?.isNotEmpty ?? false)
      ? _Step.review
      : _Step.count;
  late final List<Patient> _chosen = [...?widget.initial];

  /// Slots to fill in this collection step. The estimate uses this count;
  /// the final review and cart use only the patients actually chosen.
  int _target = 1;

  int get _amount => widget.package.priceValue * _chosen.length;

  void _selectCount(int n) {
    setState(() {
      _target = n;
      _chosen.clear();
      _step = _Step.collecting;
    });
  }

  void _addAnotherFromReview() {
    setState(() {
      _target = _chosen.length + 1;
      _step = _Step.collecting;
    });
  }

  void _useSaved(Patient patient) {
    if (_chosen.any((p) => p.id == patient.id) || _chosen.length >= _target) {
      return;
    }
    setState(() {
      _chosen.add(patient);
      if (_chosen.length >= _target) _step = _Step.review;
    });
  }

  Future<void> _addNew() async {
    final saved = await PatientFormSheet.show(context);
    if (saved != null && mounted) _useSaved(saved);
  }

  void _removeFromReview(int index) {
    setState(() {
      _chosen.removeAt(index);
      // Nothing left to confirm — start over from the headcount picker
      // rather than showing a review screen with nothing in it (and no
      // price to show for it).
      if (_chosen.isEmpty) _step = _Step.count;
    });
  }

  Widget _header(String title, {VoidCallback? onBack}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.textDark,
              tooltip: 'Back',
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textDark,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.searchBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              switch (_step) {
                _Step.count => _CountStep(
                  maxPatients: LabCartService.maxPatients,
                  selected: _target,
                  onSelect: _selectCount,
                  header: _header('Select number of patients'),
                ),
                _Step.collecting => _CollectingStep(
                  priceSummary:
                      '$_target ${_target == 1 ? 'patient' : 'patients'} × ₹${formatRupees(widget.package.priceValue)} = ₹${formatRupees(widget.package.priceValue * _target)}',
                  onUseSaved: _useSaved,
                  onAddNew: _addNew,
                  excludeIds: _chosen.map((p) => p.id).toSet(),
                  header: _header(
                    'Patient ${_chosen.length + 1} of $_target',
                    onBack: () => setState(() {
                      _step = _chosen.isEmpty ? _Step.count : _Step.review;
                    }),
                  ),
                ),
                _Step.review => _ReviewStep(
                  patients: _chosen,
                  amount: _amount,
                  unitPrice: widget.package.priceValue,
                  maxPatients: LabCartService.maxPatients,
                  onRemove: _removeFromReview,
                  onAddAnother: _addAnotherFromReview,
                  onConfirm: () => Navigator.of(context).pop(_chosen),
                  header: _header('Confirm patients'),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 1 — the old headcount picker, exactly that shape: a plain radio
/// list, one row per count up to the cart's own cap. Tapping a row advances
/// immediately; there is no separate "Continue" button, same as the sheet
/// this replaces.
class _CountStep extends StatelessWidget {
  final int maxPatients;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget header;

  const _CountStep({
    required this.maxPatients,
    required this.selected,
    required this.onSelect,
    required this.header,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const Divider(height: 1, color: AppColors.border),
        for (var n = 1; n <= maxPatients; n++) ...[
          InkWell(
            onTap: () => onSelect(n),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      n == 1 ? '1 patient' : '$n patients',
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Icon(
                    n == selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: n == selected
                        ? AppColors.brandBlue
                        : AppColors.searchBorder,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Step 2 — one slot at a time: a saved patient as a one-tap shortcut, or a
/// real blank patient+address form via [PatientFormSheet] (the old-style
/// combined create). Advances to the next slot (or review, once full) the
/// moment either resolves.
class _CollectingStep extends StatelessWidget {
  final String priceSummary;
  final ValueChanged<Patient> onUseSaved;
  final VoidCallback onAddNew;
  final Set<String> excludeIds;
  final Widget header;

  const _CollectingStep({
    required this.priceSummary,
    required this.onUseSaved,
    required this.onAddNew,
    required this.excludeIds,
    required this.header,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PatientBook.instance,
      builder: (context, _) {
        final saved = [
          for (final p in PatientBook.instance.patients)
            if (!excludeIds.contains(p.id)) p,
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                priceSummary,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Add a new patient, or pick one already on this account.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAddNew,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                  label: const Text(
                    'Add a new patient',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            if (saved.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Or choose a saved patient',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.32,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: saved.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final patient = saved[index];
                    return InkWell(
                      onTap: () => onUseSaved(patient),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patient.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              patient.summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

/// Review distinct named patients and the per-patient price before booking.
class _ReviewStep extends StatelessWidget {
  final List<Patient> patients;
  final int amount;
  final int unitPrice;
  final int maxPatients;
  final ValueChanged<int> onRemove;
  final VoidCallback onAddAnother;
  final VoidCallback onConfirm;
  final Widget header;

  const _ReviewStep({
    required this.patients,
    required this.amount,
    required this.unitPrice,
    required this.maxPatients,
    required this.onRemove,
    required this.onAddAnother,
    required this.onConfirm,
    required this.header,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            '${patients.length} ${patients.length == 1 ? 'patient' : 'patients'} × ₹${formatRupees(unitPrice)} = ₹${formatRupees(amount)}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.brandBlue,
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: patients.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, index) {
              final patient = patients[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            patient.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => onRemove(index),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: AppColors.textMuted,
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (patients.length < maxPatients) ...[
          const Divider(height: 1, color: AppColors.border),
          InkWell(
            onTap: onAddAnother,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 20,
                    color: AppColors.brandBlue,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Add another patient',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Add · ₹${formatRupees(amount)}',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
