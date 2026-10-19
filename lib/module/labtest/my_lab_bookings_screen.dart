import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend/lab_booking_repository.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_service.dart';
import 'lab_booking_detail_screen.dart';
import 'lab_booking_record.dart';
import 'lab_report_screen.dart';

/// The member's lab bookings, newest first — where each is in the lab's
/// process, when it is scheduled, any note from the lab, and, once the lab has
/// attached it, the report.
///
/// Opened from Account → My Lab Bookings.
class MyLabBookingsScreen extends StatefulWidget {
  /// Where bookings and reports come from. Defaults to the live database; a
  /// test passes its own.
  final LabBookingSource? source;

  const MyLabBookingsScreen({super.key, this.source});

  /// The screen over the real data, for a menu row to push.
  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const MyLabBookingsScreen()));

  @override
  State<MyLabBookingsScreen> createState() => _MyLabBookingsScreenState();
}

class _MyLabBookingsScreenState extends State<MyLabBookingsScreen>
    with WidgetsBindingObserver {
  late final LabBookingSource _source = widget.source ?? _liveSource();
  List<LabBookingRecord>? _bookings;
  bool _loading = true;
  bool _refreshing = false;
  Timer? _refreshTimer;

  static LabBookingSource _liveSource() {
    String phone() => AuthService.instance.currentUser.value?.phone ?? '';
    return LabBookingSource(
      loadBookings: () =>
          LabBookingRepository.instance.fetchForMember(phone: phone()),
      loadReportPages: (id) => LabBookingRepository.instance.fetchReportPages(
        bookingId: id,
        phone: phone(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // A booking's stage (Requested → Confirmed → Sample collected →
    // Completed) moves entirely from the lab's own console — nothing the member
    // does here changes it — so without this the only way to see a status
    // the lab just set is to leave and reopen the screen. Same 15s-while-
    // open, foreground-and-current-route-only rule as OrderTrackScreen /
    // UploadPrescriptionScreen use for product and prescription orders.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final bookings = await _source.loadBookings();
      if (!mounted) {
        return;
      }
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = _bookings == null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bookings = _bookings;
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'My Lab Bookings',
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
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brandBlue),
            )
          : bookings == null
          ? _Notice(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load your bookings',
              body: 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: _reload,
            )
          : bookings.isEmpty
          ? const _Notice(
              icon: Icons.biotech_outlined,
              title: 'No lab bookings yet',
              body:
                  'Tests you book from Health & Labs appear here, with their '
                  'status and your report.',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: bookings.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) =>
                    _BookingCard(booking: bookings[i], source: _source),
              ),
            ),
    );
  }
}

/// One row of the list — a compact summary, the same shape My Orders' own
/// cards use (id, status, a one-line subtitle, action buttons). Everything
/// that used to sit inline here — the stage graph, schedule, lab note —
/// now lives on [LabBookingDetailScreen], a tap away behind "Track
/// booking", instead of making every row in the list as tall as the one
/// booking a member actually came to check on.
class _BookingCard extends StatelessWidget {
  final LabBookingRecord booking;
  final LabBookingSource source;

  const _BookingCard({required this.booking, required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LabBookingDetailScreen(
                        booking: booking,
                        source: source,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.timeline_outlined, size: 18),
                  label: const Text(
                    'Track booking',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: const BorderSide(color: AppColors.brandBlue),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              if (booking.reportAvailable) ...[
                const SizedBox(width: 10),
                Expanded(
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The status pill a booking card and its detail screen both show — "Lab
/// orders" read the same status language wherever a member sees them.
class LabStageChip extends StatelessWidget {
  final LabStage stage;

  const LabStageChip({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (stage) {
      LabStage.reportReady => (AppColors.brandGreenDark, AppColors.greenTint),
      LabStage.cancelled => (AppColors.danger, AppColors.dangerTint),
      _ => (AppColors.brandBlue, AppColors.chipBlueTint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        stage.label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// Requested → Confirmed → Sample collected → Completed, with everything up
/// to the current stage filled in. Shown on [LabBookingDetailScreen].
class LabStageBar extends StatelessWidget {
  final LabStage stage;

  const LabStageBar({super.key, required this.stage});

  static const _steps = [
    LabStage.requested,
    LabStage.confirmed,
    LabStage.sampleCollected,
    LabStage.reportReady,
  ];

  @override
  Widget build(BuildContext context) {
    final reached = _steps.indexOf(stage);
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: i <= reached
                        ? AppColors.brandGreen
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _steps[i].label,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: i == reached
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: i <= reached
                        ? AppColors.textDark
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (i != _steps.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
