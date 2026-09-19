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

/// The tracker for one [Purchase]: the stages it moves through, where it is
/// now, and the promise printed above them.
///
/// Everything here is derived from the order — its kind, its status, whether
/// it has been priced and paid. Nothing new is stored, so the graph can never
/// drift from the order it describes.
class OrderTrack {
  final Purchase order;

  OrderTrack(this.order);

  bool get isCancelled => order.status == OrderStatus.cancelled;

  bool get isDelivered => order.status == OrderStatus.delivered;

  bool get awaitingPayment => order.awaitingPayment;

  /// A prescription order is priced once a real bill has been attached.
  bool get _priced => order.mrpTotal > 0 || order.paidTotal > 0;

  /// The stage the order sits on, as an index into [_stageTitles].
  int get _reachedIndex {
    switch (order.status) {
      case OrderStatus.delivered:
        return 3;
      case OrderStatus.outForDelivery:
        return 2;
      case OrderStatus.processing:
        return 1;
      case OrderStatus.cancelled:
        return 0;
    }
  }

  List<String> get _stageTitles =>
      const ['Order placed', 'Processing', 'Out for delivery', 'Delivered'];

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

    final titles = _stageTitles;
    final reached = _reachedIndex;
    return [
      for (var i = 0; i < titles.length; i++)
        TrackStep(
          title: titles[i],
          detail: i == 0 ? order.placedOn : _detailFor(i),
          // A delivered order has cleared every node, the last one included.
          state: isDelivered || i < reached
              ? TrackState.done
              : i == reached
              ? TrackState.current
              : TrackState.upcoming,
        ),
    ];
  }

  String? _detailFor(int index) {
    if (index == 3) {
      return isDelivered ? null : _deliveryBy;
    }
    if (index == 2) {
      return dispatchBy;
    }
    return null;
  }

  /// The line above the graph: what is happening at the current stage.
  String get headline {
    if (isCancelled) {
      return 'This order was cancelled.';
    }
    if (isDelivered) {
      return 'Delivered. Thanks for shopping with SHIELD.';
    }
    switch (order.status) {
      case OrderStatus.outForDelivery:
        return 'Your order is out for delivery.';
      case OrderStatus.processing:
        return 'Your order is being processed by the store.';
      case OrderStatus.delivered:
      case OrderStatus.cancelled:
        return '';
    }
  }

  /// A softer second line for the callout, or null.
  String? get subhead {
    if (isCancelled || isDelivered) {
      return null;
    }
    if (awaitingPayment) {
      return _priced
          ? 'Our store will call to confirm and collect ${order.mrpLabel}.'
          : 'You will see the price before anything is charged.';
    }
    return 'Order ${order.id}';
  }

  /// `29 Aug – 31 Aug` — the window the order is promised in, counted from the
  /// day it was placed. Falls back to a today-based window if the stored date
  /// cannot be read.
  String get _deliveryBy {
    final placed = parseDate(order.placedOn) ?? DateTime.now();
    final from = placed.add(const Duration(days: 3));
    final to = placed.add(const Duration(days: 5));
    return '${formatDayMonth(from)} – ${formatDayMonth(to)}';
  }

  /// What the "Delivery by" strip shows, or null when the order has already
  /// arrived or been called off.
  String? get deliveryWindow =>
      (order.kind == OrderKind.standard || isDelivered || isCancelled)
      ? null
      : _deliveryBy;

  /// The dispatch date shown mid-graph on the strip, `by 27 Aug`.
  String get dispatchBy {
    final placed = parseDate(order.placedOn) ?? DateTime.now();
    return 'by ${formatDayMonth(placed.add(const Duration(days: 2)))}';
  }
}
