import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import '../earnings/earnings_detail_screen.dart';
import '../earnings/member_earnings.dart';
import '../orders/purchase_service.dart';
import '../wallet/wallet_service.dart';

/// "Your savings": what buying through Sahakar 360 has been worth.
///
/// Presents the member's total savings on a rich, polished card with a soft
/// mint-emerald gradient, decorative watermark glyph, and a clear call-to-action
/// leading to the dedicated [EarningsDetailScreen].
class EarningsSection extends StatelessWidget {
  const EarningsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        PurchaseService.instance,
        WalletService.instance,
      ]),
      builder: (context, _) {
        final earned = MemberEarnings.saved;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EarningsDetailScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
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
                      color: const Color(0xFF5A8127).withValues(alpha: 0.09),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: AppColors.textDark.withValues(alpha: 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Subtle decorative background watermark
                    Positioned(
                      right: -12,
                      bottom: -16,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.07,
                          child: Icon(
                            Icons.savings_rounded,
                            size: 112,
                            color: AppColors.brandGreenDark,
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(11),
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
                                  size: 22,
                                  color: AppColors.brandGreenDeep,
                                ),
                              ),
                              const SizedBox(width: 11),
                              const Expanded(
                                child: Text(
                                  'Your savings',
                                  style: TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFCCE4C6),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Details',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.brandGreenDark,
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: AppColors.brandGreenDark,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Says in plain words what the big number below is —
                          // money kept in the member's pocket by buying here,
                          // not a balance they can spend or withdraw.
                          const Text(
                            'Total money you have saved',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                              color: AppColors.brandGreenDeep,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '₹${formatRupees(earned)}',
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      height: 1.1,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5,
                                      color: AppColors.brandGreenDark,
                                    ),
                                  ),
                                ),
                              ),
                              if (MemberEarnings.savedPercentLabel != '0%') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.brandGreenDark,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${MemberEarnings.savedPercentLabel} saved',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            earned == 0
                                ? 'Buy at Sahakar 360 prices and the difference is yours.'
                                : 'Kept out of ₹${formatRupees(MemberEarnings.totalPrice)} of total price.',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
