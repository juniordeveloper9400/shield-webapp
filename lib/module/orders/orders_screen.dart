import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend/order_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import 'order_bill_screen.dart';
import 'order_track_screen.dart';
import 'purchase_service.dart';

/// Order history, the Orders destination in the bottom bar.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  @override
  void initState() {
    super.initState();
    PurchaseService.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        // A destination, not a pushed route: nothing to go back to.
        automaticallyImplyLeading: false,
        title: const Text(
          'My Orders',
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
      // Read off the ledger the earnings card sums, so a list of four orders
      // and a total of a different four cannot happen.
      body: ListenableBuilder(
        listenable: PurchaseService.instance,
        builder: (context, _) {
          final service = PurchaseService.instance;
          final orders = service.purchases;
          if (orders.isEmpty && service.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brandBlue),
            );
          }
          if (orders.isEmpty) {
            return const _EmptyOrders();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _OrderCard(order: orders[index]),
          );
        },
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: AppColors.textMuted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'No orders yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Orders you place will show up here, with what you saved on each.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Purchase order;

  const _OrderCard({required this.order});

  /// A prescription order carries no figure until the counter has priced it.
  bool get _priced => order.mrpTotal > 0 || order.paidTotal > 0;

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
              _OrderThumbnail(order: order),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.id,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        _StatusChip(stage: order.stage),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Placed on ${order.placedOn}  ·  ${order.itemCount} item'
                      '${order.itemCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Text(
            _priced ? order.paidLabel : 'Price on confirmation',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _priced ? 17 : 14,
              fontWeight: FontWeight.w800,
              color: _priced ? AppColors.textDark : AppColors.textMuted,
            ),
          ),
          if (order.status.counts && order.saved > 0)
            Text(
              'Saved ${order.savedLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandGreenDark,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Enabled once the store has actually created a bill for this
              // order — order.billStatus comes straight off the orders
              // list's own join, so it is known without a separate fetch
              // (see Purchase.billImage's own doc for why the picture
              // itself is lazy instead).
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: order.billStatus == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrderBillScreen(order: order),
                          ),
                        ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text(
                    'Bill',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    disabledForegroundColor: AppColors.textMuted,
                    side: BorderSide(
                      color: order.billStatus == null
                          ? AppColors.border
                          : AppColors.brandBlue,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderTrackScreen(order: order),
                    ),
                  ),
                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                  label: const Text(
                    'Track order',
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
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final OrderStage stage;

  const _StatusChip({required this.stage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: stage.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        stage.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: stage.foreground,
        ),
      ),
    );
  }
}

/// The one picture that says what an order is, at a glance: the first
/// product's photo for a standard order, the uploaded scan for a
/// prescription order — a "+N" badge when there is more than one — rather
/// than the same generic square for every card in the list.
///
/// Fetches lazily per card, same reasoning as [PrescriptionUploadedCard] /
/// [OrderItemsCard] on the order's own detail screen: a picture is a `data:`
/// URI that does not belong on every row of `GET /v1/member/orders`'s list.
/// Best-effort: while loading, or when nothing comes back, the fallback icon
/// below stands in — never an error in its place.
class _OrderThumbnail extends StatefulWidget {
  final Purchase order;

  const _OrderThumbnail({required this.order});

  @override
  State<_OrderThumbnail> createState() => _OrderThumbnailState();
}

class _OrderThumbnailState extends State<_OrderThumbnail> {
  String? _image;
  int _extra = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final backendId = widget.order.backendId;
    if (backendId == null) {
      return;
    }
    if (widget.order.kind == OrderKind.prescription) {
      final rows = await OrderRepository.instance.fetchPrescriptions(backendId);
      if (!mounted || rows == null) return;
      _apply(images: rows.map((r) => r.image).toList(), total: rows.length);
    } else {
      final rows = await OrderRepository.instance.fetchItems(backendId);
      if (!mounted || rows == null) return;
      _apply(images: rows.map((r) => r.image).toList(), total: rows.length);
    }
  }

  void _apply({required List<String?> images, required int total}) {
    setState(() {
      _image = images.firstWhere((i) => i != null, orElse: () => null);
      _extra = total > 1 ? total - 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallbackIcon = widget.order.kind == OrderKind.prescription
        ? Icons.description_rounded
        : Icons.medication_outlined;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.pageTint,
              border: Border.all(color: AppColors.border),
            ),
            child: AppImage(
              image: _image,
              fit: BoxFit.cover,
              fallbackIcon: fallbackIcon,
              iconSize: 22,
              iconColor: AppColors.brandBlue,
            ),
          ),
        ),
        if (_extra > 0)
          Positioned(
            right: -5,
            bottom: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandBlue,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.white, width: 1.5),
              ),
              child: Text(
                '+$_extra',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
