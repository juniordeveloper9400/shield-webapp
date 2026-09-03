import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
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

  const PrescriptionDetailCard({
    super.key,
    required this.record,
    required this.copy,
    required this.onDelete,
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
          _Header(record: record, ready: ready),
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
                const SizedBox(height: 13),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 11),
                if (record.isAwaitingOrder)
                  _InfoStrip(
                    icon: Icons.local_shipping_outlined,
                    title: copy.deliveryDetails,
                    detail: copy.beforeOrderNote,
                  )
                else if (record.awaitingPharmacist)
                  _InfoStrip(
                    icon: Icons.hourglass_top_rounded,
                    title: copy.orderPlacedTitle,
                    detail: copy.orderPlacedDetail,
                  )
                else
                  _IntakeSection(
                    record: record,
                    copy: copy,
                    expanded: _expanded,
                    onToggle: () => setState(() => _expanded = !_expanded),
                  ),
              ],
            ),
          ),
          _DeleteBar(label: copy.delete, onDelete: widget.onDelete),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PrescriptionRecord record;
  final bool ready;

  const _Header({required this.record, required this.ready});

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
                  record.fileName,
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
                  color: ready
                      ? AppColors.brandGreenDark
                      : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ],
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
    final noun =
        count == 1 ? copy.medicineSingular : copy.medicinePlural;

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

/// The foot of the card: just the one destructive action, kept quiet.
class _DeleteBar extends StatelessWidget {
  final String label;
  final VoidCallback onDelete;

  const _DeleteBar({required this.label, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.danger,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
