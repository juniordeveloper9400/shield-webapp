import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'order_detail_sections.dart';
import 'order_track.dart';
import 'purchase_service.dart';

/// Where an order has got to, drawn as a graph.
///
/// Opened from the **Track order** button in My Orders. Product orders follow
/// the admin order status; prescriptions retain their review/billing stages.
class OrderTrackScreen extends StatefulWidget {
  final Purchase order;

  const OrderTrackScreen({super.key, required this.order});

  @override
  State<OrderTrackScreen> createState() => _OrderTrackScreenState();
}

class _OrderTrackScreenState extends State<OrderTrackScreen>
    with WidgetsBindingObserver {
  /// Starts as [OrderTrackScreen.order] and is swapped for the freshly
  /// reloaded copy once [_loadBill] lands, so a bill sent (or paid) while
  /// this screen is already open — the admin console runs on its own,
  /// independent of whatever this member happens to be looking at — shows
  /// up here rather than only on the next visit from My Orders.
  late Purchase _order = widget.order;
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PurchaseService.instance.addListener(_syncOrder);
    _syncOrder();
    unawaited(_loadBill());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_loadBill());
      }
    });
  }

  void _syncOrder() {
    if (!mounted) return;
    for (final purchase in PurchaseService.instance.purchases) {
      if (purchase.id == widget.order.id) {
        setState(() => _order = purchase);
        return;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadBill());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    PurchaseService.instance.removeListener(_syncOrder);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A full reload, not just [PurchaseService.ensureBillLoaded]'s own bill
  /// image fetch: payment status, bill amount and bill status can all move
  /// while the member is sitting on this exact screen (the admin console
  /// sends a bill, or collects it — a wallet-and-cash split, an OTP
  /// verification, none of it triggered from this device), and nothing
  /// else would otherwise prompt an already-open Track Order to catch up.
  Future<void> _loadBill() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await PurchaseService.instance.refresh();
      if (!mounted) return;
      await PurchaseService.instance.ensureBillLoaded(_order);
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final track = OrderTrack(order);

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Track order',
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
      body: Column(
        children: [
          // Where the order stands is what a member opens this screen to
          // read, so it stays put at the top rather than scrolling away
          // under everything else on the page — a shadow marks it off as
          // fixed rather than just the first card in the list.
          Container(
            decoration: BoxDecoration(
              color: AppColors.pageTint,
              boxShadow: [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              children: [
                _StatusHeader(order: order),
                const SizedBox(height: 12),
                _TrackCard(track: track),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                if (order.kind == OrderKind.prescription) ...[
                  PrescriptionUploadedCard(order: order),
                  const SizedBox(height: 14),
                ],
                DeliverToCard(order: order),
                if (order.status == OrderStatus.processing) ...[
                  const SizedBox(height: 14),
                  CancelOrderCard(order: order),
                ],
                const SizedBox(height: 14),
                const NeedHelpCard(),
                if (order.hasBill) ...[
                  const SizedBox(height: 14),
                  StoreInvoiceCard(order: order),
                ],
                const SizedBox(height: 14),
                BillDetailsCard(order: order),
                const SizedBox(height: 14),
                const SocialMediaCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _statusHeadline(OrderStatus status) {
  switch (status) {
    case OrderStatus.delivered:
      return 'Order completed';
    case OrderStatus.outForDelivery:
      return 'Out for delivery';
    case OrderStatus.processing:
      return 'Order processing';
    case OrderStatus.cancelled:
      return 'Order cancelled';
  }
}

IconData _statusIcon(OrderStatus status) {
  switch (status) {
    case OrderStatus.delivered:
      return Icons.check_circle_rounded;
    case OrderStatus.outForDelivery:
      return Icons.local_shipping_rounded;
    case OrderStatus.processing:
      return Icons.inventory_2_rounded;
    case OrderStatus.cancelled:
      return Icons.cancel_rounded;
  }
}

class _StatusHeader extends StatelessWidget {
  final Purchase order;

  const _StatusHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order.status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: status.foreground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(status), size: 20, color: AppColors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              order.kind == OrderKind.standard &&
                      status == OrderStatus.delivered
                  ? 'Order delivered'
                  : _statusHeadline(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            order.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsed by default — opening this screen leads with just the step
/// graph, where the order stands at a glance. The delivery window, the
/// "what's happening now" callout and the item/price line are the detail
/// view, one tap away rather than always taking over the top of the screen.
class _TrackCard extends StatefulWidget {
  final OrderTrack track;

  const _TrackCard({required this.track});

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final steps = track.steps;
    final currentIndex = steps.indexWhere((s) => s.state == TrackState.current);
    // The caret hangs under the centre of the current node: nodes divide the
    // width evenly, so node i is centred at (i + 0.5) / n across it.
    final caretX = steps.isEmpty || currentIndex < 0
        ? 0.0
        : ((currentIndex + 0.5) / steps.length) * 2 - 1;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_expanded && track.deliveryWindow != null)
            Container(
              color: AppColors.offerTint,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Text(
                      'Delivery by: ',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      track.deliveryWindow!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
              child: Column(
                children: [
                  _StepGraph(steps: steps),
                  const SizedBox(height: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: AppColors.textMuted,
                  ),
                  if (_expanded) ...[
                    const SizedBox(height: 12),
                    _Callout(
                      icon: _statusIcon(track.order.status),
                      title: track.headline,
                      sub: track.subhead,
                      caretX: caretX,
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.shopping_bag_outlined,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${track.order.itemCount} '
                            'item${track.order.itemCount == 1 ? '' : 's'} ordered',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textBody,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            track.order.mrpTotal > 0 ||
                                    track.order.paidTotal > 0
                                ? track.order.paidLabel
                                : 'Price on confirmation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The horizontal stage graph: a node per stage, joined by a bar that turns
/// green behind every stage the order has cleared.
class _StepGraph extends StatelessWidget {
  final List<TrackStep> steps;

  const _StepGraph({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 26,
                  child: Row(
                    children: [
                      Expanded(child: _bar(i, left: true)),
                      _Dot(state: steps[i].state),
                      Expanded(child: _bar(i, left: false)),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  steps[i].title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: steps[i].state == TrackState.upcoming
                        ? FontWeight.w500
                        : FontWeight.w700,
                    color: steps[i].state == TrackState.upcoming
                        ? AppColors.textMuted
                        : AppColors.textDark,
                  ),
                ),
                if (steps[i].detail != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    steps[i].detail!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _bar(int i, {required bool left}) {
    final atEnd = left ? i == 0 : i == steps.length - 1;
    if (atEnd) {
      return const SizedBox.shrink();
    }
    // The left bar is travelled once this node is reached; the right bar once
    // the next one is. The two halves either side of a boundary always agree.
    final reached = left
        ? steps[i].state != TrackState.upcoming
        : steps[i + 1].state != TrackState.upcoming;
    return Container(
      height: 3,
      color: reached ? AppColors.brandGreen : AppColors.border,
    );
  }
}

class _Dot extends StatelessWidget {
  final TrackState state;

  const _Dot({required this.state});

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case TrackState.done:
        return Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: AppColors.brandGreenDeep,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 14,
            color: AppColors.white,
          ),
        );
      case TrackState.current:
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brandBlue, width: 3),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.brandBlue,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      case TrackState.upcoming:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.searchBorder, width: 2),
          ),
        );
    }
  }
}

/// The blue bubble under the graph, with a caret that points up at the stage
/// the order is on.
class _Callout extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final double caretX;

  const _Callout({
    required this.icon,
    required this.title,
    required this.sub,
    required this.caretX,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 8,
          child: Align(
            alignment: Alignment(caretX.clamp(-1.0, 1.0), 1),
            child: CustomPaint(
              size: const Size(18, 8),
              painter: _CaretPainter(AppColors.brandBlue),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.brandBlue,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: AppColors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub!,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: AppColors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CaretPainter extends CustomPainter {
  final Color color;

  _CaretPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CaretPainter oldDelegate) => oldDelegate.color != color;
}
