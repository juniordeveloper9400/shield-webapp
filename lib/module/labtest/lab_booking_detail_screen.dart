import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import 'lab_booking_record.dart';
import 'lab_report_screen.dart';
import 'my_lab_bookings_screen.dart' show LabBillRow, LabStageBar, LabStageChip;

/// The order page for one lab booking — opened from "View order" on Lab
/// Orders, the same relationship My Orders' own list has with
/// [OrderTrackScreen]. Where the order is (the stage progress), what was
/// ordered and what it costs (the order summary), how and where the sample is
/// collected, any note from the lab, and the report once ready — all as the
/// lab's console has them.
class LabBookingDetailScreen extends StatelessWidget {
  final LabBookingRecord booking;
  final LabBookingSource source;

  const LabBookingDetailScreen({
    super.key,
    required this.booking,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    final scheduled = booking.scheduledFor;
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Order details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        booking.packageName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    LabStageChip(stage: booking.stage),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${booking.code} · ${booking.patients} '
                  '${booking.patients == 1 ? 'patient' : 'patients'} · '
                  '₹${formatRupees(booking.total.round())}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textMuted,
                  ),
                ),
                if (booking.createdAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Placed on ${formatDateTime12h(booking.createdAt!)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if (booking.stage != LabStage.cancelled) ...[
                  const SizedBox(height: 18),
                  LabStageBar(stage: booking.stage),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _OrderSummaryCard(booking: booking),
          const SizedBox(height: 12),
          _CollectionCard(booking: booking, scheduled: scheduled),
          if (booking.note.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.info_outline_rounded,
              title: 'NOTE FROM THE LAB',
              body: booking.note,
            ),
          ],
          if (booking.reportAvailable) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        LabReportScreen(booking: booking, source: source),
                  ),
                ),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text(
                  booking.reportPages == 1
                      ? 'View report'
                      : 'View report (${booking.reportPages} pages)',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
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

BoxDecoration _cardDecoration() => BoxDecoration(
  color: AppColors.white,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: AppColors.border),
);

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionTitle({required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.brandBlue),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// What was ordered and what it comes to — the test, who it is for, the price
/// per patient and any visit charges the lab added, ending in the total.
class _OrderSummaryCard extends StatelessWidget {
  final LabBookingRecord booking;

  const _OrderSummaryCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final extras = booking.fuelCharge + booking.techFee;
    final testsAmount = booking.unitPrice > 0
        ? booking.unitPrice * booking.patients
        : (booking.total - extras).clamp(0, double.infinity).toDouble();
    return Container(
      width: double.infinity,
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.receipt_long_outlined,
            title: 'Order summary',
            trailing: booking.isVerified
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.greenTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Verified by lab',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandGreenDark,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            booking.packageName,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          if (booking.patientList.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final patient in booking.patientList)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 15,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        patient.label,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textBody,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.border),
          ),
          LabBillRow(
            label: booking.unitPrice > 0
                ? 'Tests · ₹${formatRupees(booking.unitPrice.round())} × '
                      '${booking.patients} '
                      '${booking.patients == 1 ? 'patient' : 'patients'}'
                : 'Tests (${booking.patients} '
                      '${booking.patients == 1 ? 'patient' : 'patients'})',
            amount: '₹${formatRupees(testsAmount.round())}',
          ),
          if (booking.fuelCharge > 0) ...[
            const SizedBox(height: 5),
            LabBillRow(
              label: 'Fuel distance charge',
              amount: '+₹${formatRupees(booking.fuelCharge.round())}',
            ),
          ],
          if (booking.techFee > 0) ...[
            const SizedBox(height: 5),
            LabBillRow(
              label: 'Technician visit fee',
              amount: '+₹${formatRupees(booking.techFee.round())}',
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppColors.border),
          ),
          LabBillRow(
            label: booking.isVerified ? 'Total Bill Amount' : 'Total',
            amount: '₹${formatRupees(booking.total.round())}',
            isTotal: true,
          ),
          if (!booking.isVerified && booking.stage != LabStage.cancelled) ...[
            const SizedBox(height: 6),
            const Text(
              'The lab confirms the final bill, including any visit charges.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// How the sample is collected and where — the details the lab sets from its
/// console: home visit or branch visit, the branch, the schedule, the
/// collection address and who is assigned to collect.
class _CollectionCard extends StatelessWidget {
  final LabBookingRecord booking;
  final DateTime? scheduled;

  const _CollectionCard({required this.booking, required this.scheduled});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Collection', booking.homeCollection ? 'Home collection' : 'Store visit'),
      if (booking.storeName.isNotEmpty) ('Branch', booking.storeName),
      if (scheduled != null && booking.stage != LabStage.cancelled)
        ('Scheduled', formatDateTime12h(scheduled!))
      else if (booking.stage != LabStage.cancelled)
        ('Scheduled', 'The lab will confirm a time'),
      if (booking.homeCollection && booking.address.isNotEmpty)
        ('Address', booking.address),
      if (booking.homeCollection && booking.collectorName.isNotEmpty)
        ('Collected by', booking.collectorName),
    ];
    return Container(
      width: double.infinity,
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.local_shipping_outlined,
            title: 'Sample collection',
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    rows[i].$1,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
