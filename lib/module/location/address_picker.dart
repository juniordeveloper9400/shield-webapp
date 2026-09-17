import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'address_book.dart';
import 'address_selection_screen.dart';

/// "Deliver to" — the same compact chevron-row shape `PatientPicker` uses for
/// "Prescription is for", so choosing an address reads as the same kind of
/// question right next to it. Opens the full "Select delivery address"
/// screen (saved addresses, plus "Add address") rather than a bottom sheet
/// of its own — that screen already does everything this needs and is the
/// same one every other delivery-address surface in the app uses.
class AddressPicker extends StatelessWidget {
  final Address? selected;
  final ValueChanged<Address> onSelect;

  final String label;
  final String hint;

  const AddressPicker({
    super.key,
    required this.selected,
    required this.onSelect,
    this.label = 'Deliver to',
    this.hint = 'Select delivery address',
  });

  Future<void> _choose(BuildContext context) async {
    final chosen = await Navigator.of(context).push<Address>(
      MaterialPageRoute(builder: (_) => const AddressSelectionScreen()),
    );
    if (chosen != null) {
      onSelect(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = selected;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // An unanswered choice is drawn as an open question rather than as
          // an error: nothing has gone wrong yet.
          color: address == null ? AppColors.searchBorder : AppColors.brandBlue,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _choose(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 22,
                color: address == null
                    ? AppColors.textMuted
                    : AppColors.brandBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address == null ? hint : address.receiver,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (address != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        address.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
