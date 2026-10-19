import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import 'lab_booking_record.dart';
import 'lab_report_screen.dart';
import 'my_lab_bookings_screen.dart' show LabStageBar, LabStageChip;

/// Full tracking and detail for one lab booking — opened from "Track
/// booking" on My Lab Bookings, the same relationship My Orders' own list
/// has with its own order-track screen. Everything that used to crowd the
/// list card itself — the stage progress, schedule, and any note from the
/// lab — lives here instead.
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
          'Track booking',
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
                if (booking.stage != LabStage.cancelled) ...[
                  const SizedBox(height: 18),
                  LabStageBar(stage: booking.stage),
                ],
              ],
            ),
          ),
          if (scheduled != null && booking.stage != LabStage.cancelled) ...[
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.event_outlined,
              title: 'SCHEDULED',
              body: formatDateTime12h(scheduled),
            ),
          ],
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
