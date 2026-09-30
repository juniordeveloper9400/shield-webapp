import 'package:flutter/material.dart';

import '../../data/backend/care_repository.dart';
import '../../theme/app_colors.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';
import 'lab_store.dart';
import 'lab_store_picker_sheet.dart';

/// The branch this basket collects from — defaults to the member's home
/// branch once the live, lab-eligible list has loaded (see
/// [LabCartService.defaultStoreIfNeeded]), tappable to open
/// [LabStorePickerSheet] and choose a different one.
///
/// Shared by [LabCartScreen] and [LabCheckoutScreen] so a branch picked on
/// either screen is the exact same tile, reading and writing the one
/// [LabCartService] both of them share.
class LabBranchRow extends StatefulWidget {
  const LabBranchRow({super.key});

  @override
  State<LabBranchRow> createState() => _LabBranchRowState();
}

class _LabBranchRowState extends State<LabBranchRow> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stores = await CareRepository.instance.fetchLabStores();
    if (!mounted || stores == null) {
      return;
    }
    // Rebuilds through LabCartService's own notification, not setState here.
    LabCartService.instance.defaultStoreIfNeeded(stores);
  }

  Future<void> _choose(BuildContext context) async {
    final store = LabCartService.instance.store;
    final chosen = await LabStorePickerSheet.show(
      context,
      selectedId: store?.id,
    );
    if (chosen != null) {
      LabCartService.instance.chooseStore(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LabStore? store = LabCartService.instance.store;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _choose(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                // A missing branch blocks checkout — same red the "Deliver
                // to / Patient" rows use on the commerce checkout when
                // something required is still unset.
                color: store == null ? AppColors.danger : AppColors.border,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  size: 20,
                  color: AppColors.brandBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Branch',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        store?.name ?? 'Choose a branch',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The lab basket's bill — tests total, package discount, home collection fee
/// and the payable total, for however many patients it covers. Shared by
/// [LabCartScreen] and [LabCheckoutScreen].
class LabBillCard extends StatelessWidget {
  const LabBillCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = LabCartService.instance;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Bill summary',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _LabBillRow(
            label: 'Tests total',
            value: '₹${formatRupees(cart.mrpTotal)}',
          ),
          _LabBillRow(
            label: 'Package discount',
            value: '- ₹${formatRupees(cart.savings)}',
            accent: AppColors.brandGreenDark,
          ),
          _LabBillRow(
            label: 'Home collection',
            value: cart.collectionFee == 0
                ? 'FREE'
                : '₹${formatRupees(cart.collectionFee)}',
            accent: cart.collectionFee == 0 ? AppColors.brandGreenDark : null,
          ),
          const Divider(height: 22, color: AppColors.border),
          _LabBillRow(
            label: 'Payable',
            value: '₹${formatRupees(cart.payable)}',
            bold: true,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              cart.patientCount == 1
                  ? 'For 1 patient'
                  : 'For ${cart.patientCount} patients',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabBillRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  final bool bold;

  const _LabBillRow({
    required this.label,
    required this.value,
    this.accent,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 16 : 14,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: accent ?? (bold ? AppColors.textDark : AppColors.textBody),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
