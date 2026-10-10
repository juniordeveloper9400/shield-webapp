import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Opens a scrollable wheel of whole years and returns the one picked, or
/// null if the sheet was dismissed without choosing.
///
/// Registration forms that used to take a date of birth now take this
/// instead — see `dates.dart`'s `dobForAge`/`ageWithBirthYearLabel` for how
/// the age picked here still becomes a `DateTime` for everything downstream
/// (storage, prescriptions, KYC) that expects a date of birth, not an age.
Future<int?> pickAge(
  BuildContext context, {
  int? initialAge,
  int minAge = 1,
  int maxAge = 110,
}) {
  final start = (initialAge ?? 25).clamp(minAge, maxAge);
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _AgePickerSheet(
      initialAge: start,
      minAge: minAge,
      maxAge: maxAge,
    ),
  );
}

class _AgePickerSheet extends StatefulWidget {
  final int initialAge;
  final int minAge;
  final int maxAge;

  const _AgePickerSheet({
    required this.initialAge,
    required this.minAge,
    required this.maxAge,
  });

  @override
  State<_AgePickerSheet> createState() => _AgePickerSheetState();
}

class _AgePickerSheetState extends State<_AgePickerSheet> {
  late int _selected = widget.initialAge;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 10, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select age',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(
                initialItem: _selected - widget.minAge,
              ),
              itemExtent: 40,
              onSelectedItemChanged: (index) =>
                  setState(() => _selected = widget.minAge + index),
              children: [
                for (var age = widget.minAge; age <= widget.maxAge; age++)
                  Center(
                    child: Text(
                      '$age',
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, _selected),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
