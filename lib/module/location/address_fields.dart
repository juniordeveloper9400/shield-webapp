import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'address_book.dart';

/// The address-entry pieces shared by every place an address is captured —
/// the standalone address form, and the address details section on the
/// patient form. Kept in one file so "looks like the address form" stays
/// true by construction rather than by two screens happening to agree.

/// One line of an address — hint-only, the field's own placeholder carries
/// the question rather than a floating caption above it.
class AddressLineField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const AddressLineField({
    super.key,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB4322F)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB4322F), width: 1.4),
        ),
      ),
    );
  }
}

/// The "Current Location" button that sits beside the pincode field, wherever
/// an address is captured — the standalone address form and the patient
/// form's address section both use this one so they stay identical.
///
/// Sized to line up with [AddressLineField] beside it: the same 18px vertical
/// content padding, so pincode and button share a baseline in the row.
class CurrentLocationButton extends StatelessWidget {
  final VoidCallback onTap;

  /// Shows a spinner and ignores taps while the fix is being fetched.
  final bool loading;

  const CurrentLocationButton({
    super.key,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.offerTint,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.brandBlue.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandBlue,
                  ),
                )
              else
                const Icon(
                  Icons.my_location_rounded,
                  size: 19,
                  color: AppColors.brandBlue,
                ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  loading ? 'Locating…' : 'Current Location',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Home / Work / Other picker, wherever an address label is chosen.
class AddressLabelChips extends StatelessWidget {
  final AddressLabel selected;
  final ValueChanged<AddressLabel> onSelect;

  const AddressLabelChips({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  static const Map<AddressLabel, IconData> _icons = {
    AddressLabel.home: Icons.home_outlined,
    AddressLabel.work: Icons.work_outline_rounded,
    AddressLabel.other: Icons.location_on_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final label in AddressLabel.values)
          _AddressLabelChip(
            label: label.label,
            icon: _icons[label]!,
            isSelected: label == selected,
            onTap: () => onSelect(label),
          ),
      ],
    );
  }
}

class _AddressLabelChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _AddressLabelChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colour = isSelected ? AppColors.brandBlue : AppColors.textBody;

    return Material(
      color: isSelected ? AppColors.offerTint : AppColors.white,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isSelected ? AppColors.brandBlue : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colour),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
