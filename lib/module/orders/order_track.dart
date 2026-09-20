import '../../dates.dart';
import 'purchase_service.dart';

/// How far along a stage is.
enum TrackState { done, current, upcoming }

/// One node on the order graph: a stage, an optional line of detail under it,
/// and where the order has got to relative to it.
class TrackStep {
  final String title;
  final String? detail;
  final TrackState state;

  const TrackStep({required this.title, this.detail, required this.state});
}

/// The tracker for one [Purchase]: the four stages it moves through
/// (Placed → Store contact → Billed → Complete), where it is now, and the
/// line printed above them.
///
/// Everything here is derived from the order — [Purchase.stage] reads whether
/// the store has contacted the member, sent a bill, or completed it. Nothing
/// new is stored, so the graph can never drift from the order it describes.
class OrderTrack {
  final Purchase order;

  OrderTrack(this.order);

  OrderStage get stage => order.stage;

  bool get isCancelled => stage == OrderStage.cancelled;

  bool get isComplete => stage == OrderStage.complete;

  /// The stage the order sits on, as an index into [_stageTitles].
  int get _reachedIndex {
    switch (stage) {
      case OrderStage.placed:
      case OrderStage.cancelled:
        return 0;
      case OrderStage.storeContact:
        return 1;
      case OrderStage.billed:
        return 2;
      case OrderStage.complete:
        return 3;
    }
  }

  static const List<String> _stageTitles = [
    'Placed',
    'Store contact',
    'Billed',
    'Complete',
  ];

  /// The graph, newest stage last.
  ///
  /// A cancelled order does not walk its route — it stopped — so it is drawn
  /// as the two nodes that actually happened: placed, then called off.
  List<TrackStep> get steps {
    if (isCancelled) {
      return [
        TrackStep(
          title: _stageTitles.first,
          detail: order.placedOn,
          state: TrackState.done,
        ),
        const TrackStep(title: 'Cancelled', state: TrackState.current),
      ];
    }

    final reached = _reachedIndex;
    return [
      for (var i = 0; i < _stageTitles.length; i++)
        TrackStep(
          title: _stageTitles[i],
          detail: _detailFor(i),
          // A complete order has cleared every node, the last one included.
          state: isComplete || i < reached
              ? TrackState.done
              : i == reached
              ? TrackState.current
              : TrackState.upcoming,
        ),
    ];
  }

  /// The small date under a node — only once that step has really happened
  /// and its date is known, never a promised one.
  String? _detailFor(int index) {
    switch (index) {
      case 0:
        return order.placedOn;
      case 1:
        final at = order.storeContactedAt;
        return at == null || _reachedIndex < 1 ? null : formatDayMonth(at);
      case 2:
        final at = order.billedAt;
        return at == null || _reachedIndex < 2 ? null : formatDayMonth(at);
      default:
        return null;
    }
  }

  /// The line above the graph: what is happening at the current stage.
  String get headline {
    switch (stage) {
      case OrderStage.cancelled:
        return 'This order was cancelled.';
      case OrderStage.placed:
        return 'Your order is placed. The store will contact you soon.';
      case OrderStage.storeContact:
        return 'The store has contacted you about this order.';
      case OrderStage.billed:
        return 'Your bill is ready.';
      case OrderStage.complete:
        return 'Order complete. Thanks for shopping with Sahakar 360.';
    }
  }

  /// A softer second line for the callout, or null.
  String? get subhead {
    switch (stage) {
      case OrderStage.cancelled:
      case OrderStage.complete:
        return null;
      case OrderStage.placed:
        return 'Our store will call you to confirm the details.';
      case OrderStage.storeContact:
        return 'We are preparing your bill.';
      case OrderStage.billed:
        final label = order.billLabel;
        if (label == null) return 'Order ${order.id}';
        return order.billStatus == OrderPaymentStatus.paid
            ? '$label · Paid'
            : '$label · Payment pending';
    }
  }

  /// `29 Aug – 31 Aug` — the window a prescription order is promised in,
  /// counted from the day it was placed. Falls back to a today-based window
  /// if the stored date cannot be read.
  String get _deliveryBy {
    final placed = parseDate(order.placedOn) ?? DateTime.now();
    final from = placed.add(const Duration(days: 3));
    final to = placed.add(const Duration(days: 5));
    return '${formatDayMonth(from)} – ${formatDayMonth(to)}';
  }

  /// What the "Delivery by" strip shows, or null for a standard order, or one
  /// that is already complete or called off.
  String? get deliveryWindow =>
      (order.kind == OrderKind.standard || isComplete || isCancelled)
      ? null
      : _deliveryBy;
}
