import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../location/address_book.dart';
import '../location/address_selection_screen.dart';
import 'prescription_copy.dart';
import 'prescription_record.dart';

/// One uploaded prescription on the account, through its life:
///
///  1. **Before the order** — who it is for, who prescribed it, and a note
///     that placing the order is what sends it to the pharmacy.
///  2. **Order placed, waiting on the pharmacist** — a plain "we have it,
///     they'll call you" card. Nothing to expand yet.
///  3. **Intake card sent** — the card expands to a line per medicine with its
///     intake code and the units the pharmacist counted out.
///
/// A view, not a form: the lower half is the pharmacist's reading of the paper
/// and never the member's to type.
class PrescriptionDetailCard extends StatefulWidget {
  final PrescriptionRecord record;
  final PrescriptionCopy copy;
  final VoidCallback onDelete;

  /// Places a fresh fulfilment order for this same, already-uploaded
  /// script — a repeat medicine run without uploading it again. Null hides
  /// the affordance entirely (only offered once an order has actually been
  /// placed — see [PrescriptionRecord.ordered]).
  final VoidCallback? onReorder;

  const PrescriptionDetailCard({
    super.key,
    required this.record,
    required this.copy,
    required this.onDelete,
    this.onReorder,
  });

  /// Widths the headings and every row share, so the three columns line up.
  static const double intakeWidth = 54;
  static const double totalWidth = 52;

  @override
  State<PrescriptionDetailCard> createState() => _PrescriptionDetailCardState();
}

class _PrescriptionDetailCardState extends State<PrescriptionDetailCard> {
  bool _expanded = false;

  PrescriptionRecord get record => widget.record;
  PrescriptionCopy get copy => widget.copy;

  /// Opens the saved-addresses picker and, if something was chosen, pins it
  /// as this specific record's own delivery address — see
  /// [PrescriptionRecord.address]'s own doc. Only offered before the order
  /// is placed; once submitted the address already travelled with the order.
  Future<void> _pickAddress() async {
    final chosen = await Navigator.of(context).push<Address>(
      MaterialPageRoute(builder: (_) => const AddressSelectionScreen()),
    );
    if (chosen != null) {
      PrescriptionBook.instance.setAddress(record.id, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = record.hasIntakeCard;
    final accent = ready ? AppColors.brandGreenDeep : AppColors.border;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(record: record, ready: ready, copy: copy),
          // TEMPORARY — see PrescriptionRecord.imageDebugNote's own doc.
          if (record.imageDebugNote != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF3CD),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Text(
                record.imageDebugNote!,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.35,
                  color: Color(0xFF7A5B00),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FactRow(label: copy.patientRow, value: record.patient.name),
                const SizedBox(height: 9),
                _FactRow(
                  label: copy.doctorRow,
                  value: record.doctor.isEmpty ? '—' : record.doctor,
                  muted: record.doctor.isEmpty,
                ),
                if (record.isRecurring) ...[
                  const SizedBox(height: 9),
                  _FactRow(
                    label: copy.repeatsRow,
                    value: record.recurring!.neverExpires
                        ? '${record.recurring!.fromLabel} · '
                              '${copy.neverExpires.toLowerCase()}'
                        : '${record.recurring!.fromLabel} → '
                              '${record.recurring!.untilLabel}',
                    icon: Icons.autorenew_rounded,
                  ),
                ],
                if (record.isAwaitingOrder) ...[
                  const SizedBox(height: 9),
                  InkWell(
                    onTap: _pickAddress,
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 66,
                          child: Text(
                            copy.deliveryDetails,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            record.address == null
                                ? 'Same as default'
                                : '${record.address!.receiver}, ${record.address!.summary}',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: record.address == null
                                  ? AppColors.textMuted
                                  : AppColors.textDark,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 13),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 11),
                // hasIntakeCard wins over both the other states: the counter
                // can read a script and build its medicine list the moment
                // it is uploaded, well before the member places a
                // fulfilment order for it (insertUpload writes the row
                // straight away) — so a card sitting here still
                // "isAwaitingOrder" locally can already have real medicines
                // on it, and those must show rather than being hidden
                // behind the "pick a delivery address" note until an order
                // that may be some time away actually gets placed.
                if (record.hasIntakeCard)
                  _IntakeSection(
                    record: record,
                    copy: copy,
                    expanded: _expanded,
                    onToggle: () => setState(() => _expanded = !_expanded),
                  )
                else if (record.isAwaitingOrder)
                  _InfoStrip(
                    icon: Icons.local_shipping_outlined,
                    title: copy.deliveryDetails,
                    detail: copy.beforeOrderNote,
                  )
                else
                  _InfoStrip(
                    icon: Icons.hourglass_top_rounded,
                    title: copy.orderPlacedTitle,
                    detail: copy.orderPlacedDetail,
                  ),
              ],
            ),
          ),
          _CardFooter(
            deleteLabel: copy.delete,
            onDelete: widget.onDelete,
            reorderLabel: copy.reorder,
            onReorder: record.ordered ? widget.onReorder : null,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PrescriptionRecord record;
  final bool ready;
  final PrescriptionCopy copy;

  const _Header({
    required this.record,
    required this.ready,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ready ? AppColors.greenTint : AppColors.pageTint,
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 20,
            color: ready ? AppColors.brandGreenDark : AppColors.brandBlue,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.fileName.isEmpty
                      ? copy.noFileAttached
                      : record.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                if (record.supplyLabel.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    record.supplyLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(status: record.status, copy: copy),
          if (record.ordered) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: ready ? AppColors.brandGreenDeep : AppColors.border,
                ),
              ),
              child: Text(
                record.number,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: ready ? AppColors.brandGreenDark : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The pharmacy's own `app.prescription.status`, shown straight off the
/// backend rather than only ever inferred from local flags — a member who
/// knows the counter has "Read" their script but not yet built the intake
/// card sees exactly that, instead of the card silently staying on its
/// "before the order" state until medicines actually arrive.
class _StatusChip extends StatelessWidget {
  final String status;
  final PrescriptionCopy copy;

  const _StatusChip({required this.status, required this.copy});

  Color get _tint => switch (status.toUpperCase()) {
    'READ' => AppColors.chipBlueTint,
    'IN_CART' => AppColors.offerTint,
    'ORDERED' => AppColors.greenTint,
    _ => AppColors.chipSlateTint,
  };

  Color get _text => switch (status.toUpperCase()) {
    'READ' => AppColors.brandBlue,
    'IN_CART' => AppColors.brandBlue,
    'ORDERED' => AppColors.brandGreenDark,
    _ => AppColors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _tint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        copy.statusLabel(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: _text,
        ),
      ),
    );
  }
}

/// A label and the value beside it.
class _FactRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool muted;

  const _FactRow({
    required this.label,
    required this.value,
    this.icon,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
        if (icon != null)
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 5),
            child: Icon(icon, size: 15, color: AppColors.brandBlue),
          ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: muted ? AppColors.textMuted : AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

/// The tinted "here is what's happening" panel used before the order and while
/// the pharmacist is still working on it.
class _InfoStrip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _InfoStrip({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: AppColors.brandBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textBody,
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

/// The pharmacist's intake card: a header row that toggles, and the medicine
/// table underneath it when open.
class _IntakeSection extends StatelessWidget {
  final PrescriptionRecord record;
  final PrescriptionCopy copy;
  final bool expanded;
  final VoidCallback onToggle;

  const _IntakeSection({
    required this.record,
    required this.copy,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final count = record.medicines.length;
    final noun = count == 1 ? copy.medicineSingular : copy.medicinePlural;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            child: Row(
              children: [
                const Icon(
                  Icons.medication_outlined,
                  size: 18,
                  color: AppColors.brandGreenDark,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy.intakeCardReady,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$count $noun · '
                        '${expanded ? copy.hideMedicines : copy.viewMedicines}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.brandGreenDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.brandGreenDark,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ColumnHeadings(copy: copy),
                const SizedBox(height: 2),
                for (final medicine in record.medicines)
                  _MedicineRow(
                    medicine: medicine,
                    days: record.days,
                    copy: copy,
                  ),
                const SizedBox(height: 2),
                _IntakeLegend(copy: copy),
              ],
            ),
          ),
      ],
    );
  }
}

class _ColumnHeadings extends StatelessWidget {
  final PrescriptionCopy copy;

  const _ColumnHeadings({required this.copy});

  static const TextStyle _style = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.3,
    color: AppColors.textMuted,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(copy.product, style: _style)),
          SizedBox(
            width: PrescriptionDetailCard.intakeWidth,
            child: Text(
              copy.intake,
              textAlign: TextAlign.center,
              style: _style,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: PrescriptionDetailCard.totalWidth,
            child: Text(copy.total, textAlign: TextAlign.right, style: _style),
          ),
        ],
      ),
    );
  }
}

/// One line of the table: what to dispense, how it is taken, and how many
/// units of it the pharmacist counted out.
class _MedicineRow extends StatelessWidget {
  final PrescriptionMedicine medicine;
  final int days;
  final PrescriptionCopy copy;

  const _MedicineRow({
    required this.medicine,
    required this.days,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final intake = medicine.intake;
    final total = medicine.unitsFor(days);
    final spelled = intake.labelWith(copy.intakeSlots, copy.intakeNotSet);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine.name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  medicine.pack.isEmpty
                      ? spelled
                      : '${medicine.pack} · $spelled',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: PrescriptionDetailCard.intakeWidth,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.offerTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  intake.code,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: PrescriptionDetailCard.totalWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$total',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  copy.units,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
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

/// What the three digits mean, said once under the table.
class _IntakeLegend extends StatelessWidget {
  final PrescriptionCopy copy;

  const _IntakeLegend({required this.copy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 6),
            child: Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ),
          Expanded(
            child: Text(
              copy.intakeHelp,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The foot of the card: the one destructive action, plus — once an order
/// has actually been placed for this script — a way to place another one
/// without uploading it again.
class _CardFooter extends StatelessWidget {
  final String deleteLabel;
  final VoidCallback onDelete;
  final String reorderLabel;
  final VoidCallback? onReorder;

  const _CardFooter({
    required this.deleteLabel,
    required this.onDelete,
    required this.reorderLabel,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(
              deleteLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          if (onReorder != null)
            TextButton.icon(
              onPressed: onReorder,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: Text(
                reorderLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
