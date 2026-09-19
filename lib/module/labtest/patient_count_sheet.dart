import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';

/// "Select number of patients" — the sheet that stands between tapping Add on
/// a package and the booking landing in the lab basket.
///
/// Each row carries the price for that many patients, so the cost of adding
/// another head is visible before the choice is made rather than after.
class PatientCountSheet extends StatefulWidget {
  final LabPackage package;

  /// Pre-selected when the package is already booked, so reopening the sheet
  /// is an edit rather than a fresh choice.
  final int? initial;

  const PatientCountSheet({super.key, required this.package, this.initial});

  /// Returns the chosen patient count, or null when dismissed.
  static Future<int?> show(
    BuildContext context,
    LabPackage package, {
    int? initial,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => PatientCountSheet(package: package, initial: initial),
    );
  }

  @override
  State<PatientCountSheet> createState() => _PatientCountSheetState();
}

class _PatientCountSheetState extends State<PatientCountSheet> {
  late int? _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return SafeArea(
      top: false,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select number of patients',
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
          const Divider(height: 1, color: AppColors.border),
          // Shrink-wrapped rather than a fixed height: five rows is the whole
          // list, and the sheet should be as tall as they need.
          for (var count = 1; count <= LabCartService.maxPatients; count++) ...[
            _PatientRow(
              count: count,
              amount: widget.package.priceValue * count,
              isSelected: count == selected,
              onTap: () => setState(() => _selected = count),
            ),
            const Divider(height: 1, color: AppColors.border),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                // Disabled until a count is chosen, so the sheet cannot add a
                // booking the user has not actually decided on.
                onPressed: selected == null
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
                  selected == null
                      ? 'Select patients'
                      : 'Add · ₹${formatRupees(widget.package.priceValue * selected)}',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  final int count;
  final int amount;
  final bool isSelected;
  final VoidCallback onTap;

  const _PatientRow({
    required this.count,
    required this.amount,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                count == 1 ? '1 patient' : '$count patients',
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Text(
              '₹${formatRupees(amount)}',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.brandBlue : AppColors.textBody,
              ),
            ),
            const SizedBox(width: 14),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 24,
              color: isSelected ? AppColors.brandBlue : AppColors.searchBorder,
            ),
          ],
        ),
      ),
    );
  }
}
