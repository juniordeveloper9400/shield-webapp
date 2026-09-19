import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import 'order_bill_screen.dart';
import 'purchase_service.dart';

/// Every order the store has actually billed, newest first — the Account
/// destination's own record of what was charged and when, rather than
/// having to open each order individually to check.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
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
        title: const Text(
          'Bills',
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
      body: ListenableBuilder(
        listenable: PurchaseService.instance,
        builder: (context, _) {
          final service = PurchaseService.instance;
          // A bill exists once the store has priced the order — billImage
          // itself is fetched lazily per order (see
          // PurchaseService.ensureBillLoaded's own doc), so billStatus (set
          // straight off the orders list join) is what marks "has a bill"
          // here, not whether the picture happens to be in memory yet.
          final billed = service.purchases
              .where((order) => order.billStatus != null)
              .toList();

          if (billed.isEmpty && service.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brandBlue),
            );
          }
          if (billed.isEmpty) {
            return const _EmptyBills();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: billed.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _BillRow(order: billed[index]),
          );
        },
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final Purchase order;

  const _BillRow({required this.order});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderBillScreen(order: order)),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.pageTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 21,
                  color: AppColors.brandBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Placed on ${order.placedOn}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (order.billAmount != null)
                Text(
                  '₹${formatRupees(order.billAmount!)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              const SizedBox(width: 4),
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

class _EmptyBills extends StatelessWidget {
  const _EmptyBills();

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
              'No bills yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bills the store creates for your orders will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
