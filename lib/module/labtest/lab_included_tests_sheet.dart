import 'package:flutter/material.dart';

import '../../data/backend/care_repository.dart';
import '../../theme/app_colors.dart';
import 'lab_package.dart';
import 'lab_test_detail_screen.dart';

/// The bottom sheet an included test opens from a package's "Included in this
/// package" list: how many tests it is, its name, and every test inside it
/// with a tick. A group test lists its members (the admin's "Set Grouptest"
/// tab); a plain test lists itself. "View full details" still reaches the
/// About / Why this test / Symptoms page.
class LabIncludedTestsSheet extends StatefulWidget {
  final LabProfile profile;

  const LabIncludedTestsSheet({super.key, required this.profile});

  static Future<void> show(BuildContext context, LabProfile profile) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => LabIncludedTestsSheet(profile: profile),
    );
  }

  @override
  State<LabIncludedTestsSheet> createState() => _LabIncludedTestsSheetState();
}

class _LabIncludedTestsSheetState extends State<LabIncludedTestsSheet> {
  Future<LabTestDetail?>? _future;

  @override
  void initState() {
    super.initState();
    final id = widget.profile.testId;
    if (id != null) {
      _future = CareRepository.instance.fetchLabTestDetail(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: FutureBuilder<LabTestDetail?>(
        future: _future,
        builder: (context, snapshot) {
          final loading =
              _future != null &&
              snapshot.connectionState != ConnectionState.done;
          final detail = snapshot.data;
          final members = [
            for (final item in detail?.includedTests ?? const <LabIncludedTest>[])
              item,
          ];
          // A plain test (or one that could not be loaded) is listed as
          // itself, so the sheet is never empty.
          final lines = members.isNotEmpty
              ? members
              : [LabIncludedTest(widget.profile.name)];
          final count = members.isNotEmpty
              ? members.where((m) => !m.isSubhead).length
              : 1;
          final subtitle = (detail?.about ?? '').trim().isNotEmpty
              ? detail!.about.trim()
              : widget.profile.shortName;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 16, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 32,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandBlue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          count == 1 ? 'TEST' : 'TESTS',
                          style: const TextStyle(
                            fontSize: 12.5,
                            letterSpacing: 0.4,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.profile.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textBody,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 22),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.pageTint,
                        foregroundColor: AppColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Flexible(
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        children: [
                          for (final line in lines)
                            line.isSubhead
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      14,
                                      0,
                                      6,
                                    ),
                                    child: Text(
                                      line.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        letterSpacing: 0.3,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.brandBlue,
                                      ),
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: AppColors.border,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.check_rounded,
                                          size: 20,
                                          color: AppColors.brandGreenDark,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Text(
                                            line.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                        ],
                      ),
              ),
              if (widget.profile.testId != null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: TextButton(
                      onPressed: () {
                        final navigator = Navigator.of(context);
                        navigator.pop();
                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) => LabTestDetailScreen(
                              testId: widget.profile.testId!,
                            ),
                          ),
                        );
                      },
                      child: const Text('View full details'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
