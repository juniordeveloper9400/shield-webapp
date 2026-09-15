import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/skeleton_pulse.dart';

/// Shown in [ReferEarnCard] / [AgentPortalCard]'s exact slot on the feed
/// while [PersonaService] has not yet resolved whether the signed-in member
/// is a plain member or an agent — same padding, gradient, tile and chip
/// row as both real cards, bones in place of their text, so the eventual
/// swap to whichever one it turns out to be reads as content settling in
/// rather than a layout jolt.
class AgentCardSkeleton extends StatelessWidget {
  const AgentCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
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
        child: SkeletonPulse(
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonBox(width: 150, height: 16),
                        const SizedBox(height: 7),
                        SkeletonBox(
                          width: MediaQuery.sizeOf(context).width * 0.4,
                          height: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const SkeletonBox(
                    width: 84,
                    height: 22,
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  const SizedBox(width: 8),
                  const SkeletonBox(width: 96, height: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
