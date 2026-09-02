import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'investor_model.dart';
import 'investor_portal_screen.dart';
import 'investor_sparkline.dart';

/// Home entry point into the investor portal.
///
/// Drawn to match [AgentPortalCard] and, behind it, `ReferEarnCard` — same
/// gradient card, tile, title row and chip strip — but sits alongside
/// whichever of those a signed-in number already shows rather than replacing
/// it: being an investor says nothing about whether that same number is also
/// a member or an agent.
class InvestorAccessCard extends StatelessWidget {
  final Investor investor;

  const InvestorAccessCard({super.key, required this.investor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Material(
        color: AppColors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => InvestorPortalScreen(investor: investor),
            ),
          ),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppColors.goldTint, AppColors.offerTint],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.trending_up_rounded,
                        size: 23,
                        color: AppColors.goldAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'My Investment',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Deliberately not naming the store here: an
                          // investor can hold a stake in more than one, and
                          // this card is shared across all of them. Which
                          // outlet(s) is what opening the portal is for.
                          const Text(
                            'Track your investment return',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 24,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.goldAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${investor.totalUnits} units',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // A continuous trend line rather than a number — the
                    // stake is doing well, read at a glance without a
                    // printed code or figure to parse. The same history the
                    // portal's own return plan graphs, off the plan
                    // [Investor.planType] has it fixed to.
                    Expanded(
                      child: TrendSparkline(
                        values: investor.returnHistory(
                          yearly: investor.planType == InvestorPlanType.yearly,
                        ),
                        height: 30,
                        // Too small a strip for the area wash to read as
                        // anything but noise — the line alone carries it.
                        filled: false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

