import 'package:flutter/material.dart';

import '../../data/backend/care_repository.dart';
import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../location/address_book.dart';
import '../location/address_selection_screen.dart';
import '../patients/patient_book.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';
import 'lab_store.dart';
import 'lab_store_picker_sheet.dart';

/// Lets the member pick how their sample reaches the lab — the lab visits
/// them (home collection, the default) or they visit the branch themselves
/// (store visit). Only home collection needs a delivery address, so
/// [LabCheckoutScreen] shows/requires [LabAddressRow] only while this is set
/// to home collection.
class LabFulfillmentRow extends StatelessWidget {
  const LabFulfillmentRow({super.key});

  @override
  Widget build(BuildContext context) {
    final chosen = LabCartService.instance.fulfillmentType;

    return Row(
      children: [
        Expanded(
          child: _FulfillmentOption(
            label: 'Home Collection',
            icon: Icons.home_outlined,
            selected: chosen == LabFulfillmentType.homeCollection,
            onTap: () => LabCartService.instance
                .chooseFulfillmentType(LabFulfillmentType.homeCollection),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FulfillmentOption(
            label: 'Store Visit',
            icon: Icons.storefront_outlined,
            selected: chosen == LabFulfillmentType.storeVisit,
            onTap: () => LabCartService.instance
                .chooseFulfillmentType(LabFulfillmentType.storeVisit),
          ),
        ),
      ],
    );
  }
}

class _FulfillmentOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FulfillmentOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandBlue.withValues(alpha: 0.08) : AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brandBlue : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.brandBlue : AppColors.textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.brandBlue : AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One collection address row per distinct patient across the basket — each
/// can have their own, set via "Change" below; a patient with none of their
/// own falls back to the basket's shared [AddressBook.deliverTo].
///
/// Not `const` where it's used (see [LabFulfillmentRow]'s own note): each
/// row's build() reads [LabCartService.addressFor]/[AddressBook.deliverTo]
/// directly, so a `const` ancestor would never show a change here either.
class LabPatientAddressList extends StatelessWidget {
  final List<Patient> patients;

  const LabPatientAddressList({super.key, required this.patients});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final patient in patients) ...[
          _LabPatientAddressRow(patient: patient),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _LabPatientAddressRow extends StatelessWidget {
  final Patient patient;

  const _LabPatientAddressRow({required this.patient});

  Future<void> _choose(BuildContext context) async {
    final chosen = await Navigator.of(context).push<Address>(
      MaterialPageRoute(builder: (_) => const AddressSelectionScreen()),
    );
    if (chosen != null) {
      LabCartService.instance.setAddressFor(patient, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    // This patient's own address, else the basket's shared one — same
    // precedence LabCheckoutScreen's own `_everyPatientHasAddress` follows.
    final address =
        LabCartService.instance.addressFor(patient) ??
        AddressBook.instance.deliverTo;

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _choose(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              // A missing address blocks checkout — same red the branch
              // row below uses when nothing is chosen yet.
              color: address == null ? AppColors.danger : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 20,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      address == null
                          ? 'Choose a collection address'
                          : '${address.label.label} (${address.pincode})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (address != null) ...[
                      const SizedBox(height: 2),
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
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
        // Blue once a branch is actually chosen — the same "this is the
        // selected one" treatment the Home Collection / Store Visit cards
        // above use, rather than looking identical to an empty row.
        color: store == null ? AppColors.white : AppColors.brandBlue.withValues(alpha: 0.08),
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
                color: store == null ? AppColors.danger : AppColors.brandBlue,
                width: store == null ? 1 : 1.5,
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

/// Lets the member pick a preferred date for the visit/collection —
/// optional, shown on [LabCheckoutScreen] only (scheduling makes no sense
/// before a booking exists). Sent through to `backend/api` as the
/// booking's own `scheduledFor`, so the lab sees it already filled in on
/// the admin console's Schedule section instead of starting blank; the
/// lab can still change it from there regardless.
class LabScheduleRow extends StatelessWidget {
  const LabScheduleRow({super.key});

  Future<void> _choose(BuildContext context) async {
    final now = DateTime.now();
    final current = LabCartService.instance.scheduledFor;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && current.isAfter(now) ? current : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      helpText: 'Preferred date',
    );
    if (picked != null) {
      LabCartService.instance.chooseScheduledFor(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = LabCartService.instance.scheduledFor;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: date == null ? AppColors.white : AppColors.brandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _choose(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: date == null ? AppColors.border : AppColors.brandBlue,
                width: date == null ? 1 : 1.5,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.event_outlined,
                  size: 20,
                  color: AppColors.brandBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Preferred date (optional)',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        date == null ? 'Choose a date' : formatDate(date),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                if (date != null)
                  IconButton(
                    onPressed: () => LabCartService.instance.chooseScheduledFor(null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textMuted,
                    tooltip: 'Clear date',
                    visualDensity: VisualDensity.compact,
                  )
                else
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
            label: cart.fulfillmentType == LabFulfillmentType.storeVisit
                ? 'Store visit'
                : 'Home collection',
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
