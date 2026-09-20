import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../orders/order_track_screen.dart';
import '../orders/purchase_service.dart';
import 'prescription_copy.dart';
import 'prescription_record.dart';

/// Where the order a prescription was placed into has got to — the same
/// four stages as the Track order screen (Placed → Store contact → Billed →
/// Complete, or Cancelled), shown right on the prescription's card so a member
/// need not leave "Your prescriptions" to see whether the pharmacist has
/// called or a bill has been sent.
///
/// The stage is worked out by [OrderStage.derive], the same rule
/// [Purchase.stage] uses. The app's loaded order book is preferred over what
/// the prescription row reported ([PrescriptionRecord.order]) because it is
/// refreshed more often; the card falls back on the latter until the book has
/// the order, and on plain "Placed" for a prescription ordered a moment ago
/// whose link the next refresh has not seen yet.
///
/// Nothing at all for a prescription that has not been ordered.
class PrescriptionOrderStatus extends StatelessWidget {
  final PrescriptionRecord record;
  final PrescriptionCopy copy;

  const PrescriptionOrderStatus({
    super.key,
    required this.record,
    required this.copy,
  });

  /// The four stages of a live order, left to right. Cancelled is not one of
  /// them: it ends the order, so it replaces the track rather than sitting on
  /// it.
  static const List<OrderStage> track = [
    OrderStage.placed,
    OrderStage.storeContact,
    OrderStage.billed,
    OrderStage.complete,
  ];

  String _label(OrderStage stage) => switch (stage) {
    OrderStage.placed => copy.stagePlaced,
    OrderStage.storeContact => copy.stageStoreContact,
    OrderStage.billed => copy.stageBilled,
    OrderStage.complete => copy.stageComplete,
    OrderStage.cancelled => copy.stageCancelled,
  };

  String _detail(OrderStage stage) => switch (stage) {
    OrderStage.placed => copy.stagePlacedDetail,
    OrderStage.storeContact => copy.stageStoreContactDetail,
    OrderStage.billed => copy.stageBilledDetail,
    OrderStage.complete => copy.stageCompleteDetail,
    OrderStage.cancelled => copy.stageCancelledDetail,
  };

  @override
  Widget build(BuildContext context) {
    if (!record.ordered && record.order == null) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: PurchaseService.instance,
      builder: (context, _) {
        final purchase = PurchaseService.instance.purchaseFor(record.order);
        final stage =
            purchase?.stage ?? record.order?.stage ?? OrderStage.placed;
        final code = purchase?.id ?? record.order?.code;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            color: stage.background.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: stage.foreground.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    size: 18,
                    color: stage.foreground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.orderStatusTitle,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        if (code != null)
                          Text(
                            code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: stage.foreground,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _label(stage),
                      key: const ValueKey('order-stage-chip'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
              if (stage != OrderStage.cancelled) ...[
                const SizedBox(height: 12),
                _StageTrack(current: stage, label: _label),
              ],
              const SizedBox(height: 10),
              Text(
                _detail(stage),
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppColors.textBody,
                ),
              ),
              if (purchase != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderTrackScreen(order: purchase),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    iconAlignment: IconAlignment.end,
                    label: Text(copy.trackOrder),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandBlue,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The four-dot progress line: a dot per stage, joined by a line that is
/// filled up to the stage reached. Reached stages are ticked, the current one
/// is ringed, and the rest are hollow.
class _StageTrack extends StatelessWidget {
  final OrderStage current;
  final String Function(OrderStage) label;

  const _StageTrack({required this.current, required this.label});

  @override
  Widget build(BuildContext context) {
    final stages = PrescriptionOrderStatus.track;
    final reached = stages.indexOf(current);

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < stages.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2.5,
                    color: i <= reached
                        ? current.foreground
                        : AppColors.border,
                  ),
                ),
              _Dot(
                done: i < reached || current == OrderStage.complete,
                active: i == reached,
                color: current.foreground,
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < stages.length; i++)
              Expanded(
                child: Text(
                  label(stages[i]),
                  // The end labels hug their dot's edge so the row does not
                  // run past the card; the middle two centre under theirs.
                  textAlign: i == 0
                      ? TextAlign.left
                      : i == stages.length - 1
                      ? TextAlign.right
                      : TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    fontWeight: i == reached
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: i <= reached
                        ? AppColors.textDark
                        : AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final bool done;
  final bool active;
  final Color color;

  const _Dot({required this.done, required this.active, required this.color});

  @override
  Widget build(BuildContext context) {
    const size = 18.0;
    if (done) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 12, color: AppColors.white),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? color : AppColors.border,
          width: active ? 4 : 2,
        ),
      ),
    );
  }
}
