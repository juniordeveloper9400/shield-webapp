import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/skeleton_pulse.dart';

/// Shown in place of [AgentTeamSalesCard] and [AgentTeamRosterSection]
/// while [AgentService.isTeamLoaded] is still false — the rollup's blue
/// banner and headcount box, then three roster rows, all in bone, so the
/// portal's shape is already on screen the moment it opens rather than
/// popping in once the team finishes loading.
class AgentTeamSkeleton extends StatelessWidget {
  const AgentTeamSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The "Team sales" rollup card's shape: a solid banner over a
          // white headcount box.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                Container(height: 54, color: skeletonBone.withValues(alpha: 0.6)),
                Container(
                  color: AppColors.offerTint,
                  padding: const EdgeInsets.all(14),
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.border),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SkeletonBox(width: 130, height: 14),
          const SizedBox(height: 4),
          const SkeletonBox(width: 190, height: 11),
          const SizedBox(height: 12),
          // Three roster rows.
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i != 0) const Divider(height: 1, color: AppColors.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        SkeletonBox(
                          width: 7,
                          height: 7,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(child: SkeletonBox(width: 120, height: 13)),
                        const SizedBox(width: 10),
                        const SkeletonBox(width: 46, height: 12),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
