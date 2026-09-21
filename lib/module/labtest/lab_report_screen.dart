import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import 'lab_booking_record.dart';

/// The lab report for one booking — the pages the lab attached, one at a
/// time, each pinch-to-zoom. Opened from a Report-ready booking on My Lab
/// Bookings; the pages are fetched now rather than with the list, because each
/// is a full-size image.
class LabReportScreen extends StatefulWidget {
  final LabBookingRecord booking;
  final LabBookingSource source;

  const LabReportScreen({
    super.key,
    required this.booking,
    required this.source,
  });

  @override
  State<LabReportScreen> createState() => _LabReportScreenState();
}

class _LabReportScreenState extends State<LabReportScreen> {
  final _controller = PageController();
  List<String>? _pages;
  bool _loading = true;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pages = await widget.source.loadReportPages(widget.booking.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _pages = pages;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: Text(
          'Lab report · ${widget.booking.code}',
          style: const TextStyle(
            fontSize: 18,
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
          : pages == null
          ? _Message(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load the report',
              body: 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: _load,
            )
          : pages.isEmpty
          ? const _Message(
              icon: Icons.hourglass_empty_rounded,
              title: 'Report not available yet',
              body: 'The lab has not attached this report yet.',
            )
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: AppImage(
                          image: pages[i],
                          fit: BoxFit.contain,
                          fallbackIcon: Icons.broken_image_outlined,
                          iconSize: 48,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  color: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SafeArea(
                    top: false,
                    child: Text(
                      pages.length == 1
                          ? 'Page 1 of 1'
                          : 'Page ${_index + 1} of ${pages.length} — swipe for more',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({
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
