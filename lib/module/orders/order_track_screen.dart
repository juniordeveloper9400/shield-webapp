import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'order_detail_sections.dart';
import 'order_track.dart';
import 'purchase_service.dart';

/// Where an order has got to, drawn as a graph.
///
/// Opened from the **Track order** button in My Orders. The stages across the
/// top differ by [OrderKind]: a standard order is placed, packed, dispatched,
/// delivered; a prescription order gains a *received* and a *pharmacist
/// review* stage in front, because it is read and priced before it is packed.
class OrderTrackScreen extends StatefulWidget {
  final Purchase order;

  const OrderTrackScreen({super.key, required this.order});

  @override
  State<OrderTrackScreen> createState() => _OrderTrackScreenState();
}

class _OrderTrackScreenState extends State<OrderTrackScreen> {
  /// Starts as [OrderTrackScreen.order] and is swapped for the freshly
  /// merged copy once [PurchaseService.ensureBillLoaded]'s fetch lands, so
  /// the store's invoice appears in this already-open screen the moment it
  /// arrives rather than only on the next visit from My Orders.
  late Purchase _order = widget.order;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBill());
  }

  Future<void> _loadBill() async {
    await PurchaseService.instance.ensureBillLoaded(_order);
    if (!mounted) return;
    for (final purchase in PurchaseService.instance.purchases) {
      if (purchase.id == _order.id) {
        setState(() => _order = purchase);
        return;
      }
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
      // The pay bar is pinned rather than scrolled to — it is the one action
      // the screen exists to prompt, and a member should not have to reach the
      // end of the bill to find it.
      bottomNavigationBar: track.awaitingPayment
          ? OrderPayFooter(order: order)
          : null,
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
                const _ReminderRow(),
                if (order.kind == OrderKind.prescription) ...[
                  const SizedBox(height: 14),
                  const PrescriptionUploadedCard(),
                ],
                const SizedBox(height: 14),
                DeliverToCard(order: order),
                const SizedBox(height: 14),
                const EmailIdCard(),
                const SizedBox(height: 14),
                DeliveryUpdatesCard(order: order),
                if (order.status == OrderStatus.processing) ...[
                  const SizedBox(height: 14),
                  CancelOrderCard(order: order),
                ],
                const SizedBox(height: 14),
                const NeedHelpCard(),
                const SizedBox(height: 14),
                const LabPackagePromoCard(),
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
      return 'Order delivered';
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
              _statusHeadline(status),
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

class _TrackCard extends StatelessWidget {
  final OrderTrack track;

  const _TrackCard({required this.track});

  @override
  Widget build(BuildContext context) {
    final steps = track.steps;
    final currentIndex = steps.indexWhere(
      (s) => s.state == TrackState.current,
    );
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
          if (track.deliveryWindow != null)
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
            child: Column(
              children: [
                _StepGraph(steps: steps),
                const SizedBox(height: 16),
                _Callout(
                  icon: _statusIcon(track.order.status),
                  title: track.headline,
                  sub: track.subhead,
                  caretX: caretX,
                ),
                if (track.awaitingPayment) ...[
                  const SizedBox(height: 12),
                  _PayNudge(track: track),
                ],
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
                        track.order.mrpTotal > 0 || track.order.paidTotal > 0
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

/// The amber "make payment now" strip inside the card, for a prescription
/// order that has not been paid.
class _PayNudge extends StatelessWidget {
  final OrderTrack track;

  const _PayNudge({required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.goldTint,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 20,
            color: AppColors.goldAccent,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make payment now',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'To get delivery on time',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _payToast(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.goldAccent,
              side: const BorderSide(color: AppColors.goldAccent),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Pay now',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.offerTint,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('We will call you when it is time to reorder.'),
              ),
            );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 20,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Set reminder call for next order',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _payToast(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Payment opens once the pharmacist confirms the price.'),
      ),
    );
}
