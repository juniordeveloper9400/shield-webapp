import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../orders/purchase_service.dart';
import '../wallet/wallet_service.dart';
import 'member_earnings.dart';

/// Dedicated screen displaying the comprehensive breakdown of member earnings & savings.
class EarningsDetailScreen extends StatelessWidget {
  const EarningsDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Your Earnings',
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
        listenable: Listenable.merge([
          PurchaseService.instance,
          WalletService.instance,
        ]),
        builder: (context, _) {
          final orders = PurchaseService.instance;
          final earned = MemberEarnings.saved;
          final purchases = orders.purchases.where((p) => p.status.counts).toList();
          final plans = MemberEarnings.plans;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              // Hero Summary Card
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFF7FCF5),
                      Color(0xFFEAF6E7),
                      Color(0xFFDCF2D8),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFCDE8CA),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5A8127).withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      right: -10,
                      bottom: -15,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.07,
                          child: Icon(
                            Icons.savings_rounded,
                            size: 120,
                            color: AppColors.brandGreenDark,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFD6ECCF),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.textDark.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.savings_rounded,
                                  size: 24,
                                  color: AppColors.brandGreenDeep,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Total Savings & Earnings',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                    Text(
                                      '₹${formatRupees(earned)}',
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.brandGreenDark,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFCCE4C6),
                              ),
                            ),
                            child: Text(
                              earned == 0
                                  ? 'Buy at SHIELD prices and the difference is yours.'
                                  : 'You saved ${MemberEarnings.savedPercentLabel} overall, keeping ₹${formatRupees(earned)} out of ₹${formatRupees(MemberEarnings.totalPrice)} total price.',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
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

              const SizedBox(height: 16),

              // Breakdown 3-Card Grid
              Row(
                children: [
                  Expanded(
                    child: _DetailStatCard(
                      icon: Icons.local_offer_outlined,
                      label: 'Total price',
                      value: '₹${formatRupees(MemberEarnings.totalPrice)}',
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DetailStatCard(
                      icon: Icons.payments_outlined,
                      label: 'You paid',
                      value: '₹${formatRupees(MemberEarnings.paid)}',
                      color: AppColors.brandBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DetailStatCard(
                      icon: Icons.savings_outlined,
                      label: 'You saved',
                      value: '₹${formatRupees(earned)}',
                      color: AppColors.brandGreenDeep,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // Orders Breakdown Section
              const Text(
                'Earnings Breakdown by Order',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 12),

              if (purchases.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: const Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 40,
                        color: AppColors.textMuted,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No purchase earnings yet',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: purchases.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final order = purchases[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.greenTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 20,
                                color: AppColors.brandGreenDeep,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.id,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${order.placedOn} · ${order.itemCount} ${order.itemCount == 1 ? 'item' : 'items'}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '+${order.savedLabel}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brandGreenDark,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Bill ${order.mrpLabel}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textMuted,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Paid ${order.paidLabel}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textBody,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              // The other way SHIELD gives money back: not a discount on an
              // order, but the 10% SHIELD adds the moment a privilege plan is
              // activated. Its own section rather than folded into the order
              // list above — a plan is not an order, and "activated" is not
              // the same fact as "delivered".
              if (plans.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text(
                  'Health Pass Plan Bonus',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'The 10% SHIELD added when you activated each plan.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: plans.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final card = plans[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.goldTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.workspace_premium_outlined,
                                size: 20,
                                color: AppColors.goldAccent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    card.name,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${formatDate(card.issuedOn)} · activated',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '+₹${formatRupees(card.load.bonus)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brandGreenDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '10% · loaded ${card.load.amountLabel}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Explanatory Info Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.pageTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.brandBlue,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Earnings add up the direct savings on every SHIELD order — printed MRP less the discounted member price you paid — and the 10% bonus SHIELD credits when you activate a Health Pass plan.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
