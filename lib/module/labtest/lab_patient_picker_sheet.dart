import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../patients/patient_book.dart';
import '../patients/patient_form_sheet.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';

/// "Who is this for?" — the sheet that stands between tapping Add on a
/// package and the booking landing in the lab basket. Replaces the old
/// headcount-only picker: every patient booked for a test now has a real
/// name (so staff and the lab know who it's for), each able to carry its
/// own collection address later on the checkout screen.
class LabPatientPickerSheet extends StatefulWidget {
  final LabPackage package;

  /// Pre-selected when the package is already booked, so reopening the
  /// sheet is an edit rather than a fresh choice.
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

class _LabPatientPickerSheetState extends State<LabPatientPickerSheet> {
  late final List<String> _selectedIds = [
    for (final p in widget.initial ?? const <Patient>[]) p.id,
  ];

  bool get _atLimit => _selectedIds.length >= LabCartService.maxPatients;

  void _toggle(Patient patient) {
    setState(() {
      if (_selectedIds.contains(patient.id)) {
        _selectedIds.remove(patient.id);
      } else if (!_atLimit) {
        _selectedIds.add(patient.id);
      }
    });
  }

  Future<void> _addPatient() async {
    if (_atLimit) return;
    final saved = await PatientFormSheet.show(context);
    if (saved != null && mounted) {
      setState(() => _selectedIds.add(saved.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: PatientBook.instance,
        builder: (context, _) {
          final book = PatientBook.instance.patients;
          final selected = [
            for (final id in _selectedIds)
              if (PatientBook.instance.byId(id) != null) PatientBook.instance.byId(id)!,
          ];
          final amount = widget.package.priceValue * selected.length;

          return Column(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Who is this for?',
                        style: TextStyle(
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
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Pick up to ${LabCartService.maxPatients} — each can have their own collection address at checkout.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              if (book.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    'No patients on this account yet.',
                    style: TextStyle(fontSize: 14.5, color: AppColors.textBody),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: book.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final patient = book[index];
                      final isSelected = _selectedIds.contains(patient.id);
                      return _PatientCheckRow(
                        patient: patient,
                        isSelected: isSelected,
                        disabled: !isSelected && _atLimit,
                        onTap: () => _toggle(patient),
                      );
                    },
                  ),
                ),
              const Divider(height: 1, color: AppColors.border),
              InkWell(
                onTap: _atLimit ? null : _addPatient,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 21,
                        color: _atLimit ? AppColors.textMuted : AppColors.brandBlue,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Add a new patient',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: _atLimit ? AppColors.textMuted : AppColors.brandBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      selected.isEmpty
                          ? 'Select at least one patient'
                          : 'Add · ₹${formatRupees(amount)}',
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
        },
      ),
    );
  }
}

class _PatientCheckRow extends StatelessWidget {
  final Patient patient;
  final bool isSelected;
  final bool disabled;
  final VoidCallback onTap;

  const _PatientCheckRow({
    required this.patient,
    required this.isSelected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 23,
                color: isSelected ? AppColors.brandBlue : AppColors.searchBorder,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
