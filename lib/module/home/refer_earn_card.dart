import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../refer/refer_earn_screen.dart';
import '../refer/referral_level.dart';
import '../refer/referral_service.dart';

/// Home entry point into the refer-and-earn journey.
class ReferEarnCard extends StatelessWidget {
  const ReferEarnCard({super.key});

  @override
  Widget build(BuildContext context) {
    // Listens so a referral that lands (or finishes loading) while the
    // member is sitting on the home tab updates the teaser without a
    // pull-to-refresh.
    return ListenableBuilder(
      listenable: ReferralService.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    const levels = ReferralLadder.levels;
    final progress = ReferralService.instance.progress;
    final cleared = progress.currentLevel(levels);
    final next = progress.nextLevel(levels);

    // Transparent wrapper so the card sits correctly on whichever background
    // hosts it; its own gradient supplies the fill.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Material(
        color: AppColors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => ReferEarnScreen.open(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [AppColors.offerTint, AppColors.greenTint],
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
                        Icons.card_giftcard_rounded,
                        size: 23,
                        color: AppColors.brandGreenDeep,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Refer & Earn',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Climb levels, unlock reward points',
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Level $cleared of ${levels.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    if (next != null)
                      Text(
                        'Refer '
                        '${(next.referralsRequired - progress.directReferrals).clamp(0, 99)}'
                        ' more for ${next.pointsLabel}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandGreenDark,
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
