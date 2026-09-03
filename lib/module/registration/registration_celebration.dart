import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/reward_celebration.dart';
import 'registration_service.dart';

/// The beat after the registration form is submitted.
///
/// A first registration earns points, so it gets the full [RewardCelebration]
/// — the coin fills the screen, sparks, and the point count lands. An edit is
/// just a save, so it gets a plain confirmation dialog and no reward.
///
/// Resolves once the moment is over (the celebration auto-dismisses; the edit
/// dialog waits for a tap), so the caller can close the form afterwards.
Future<void> showRegistrationCelebration(
  BuildContext context, {
  required bool isEditing,
}) {
  if (isEditing) {
    return _showEditConfirmation(context);
  }
  return RewardCelebration.show(
    context,
    points: RegistrationService.rewardPoints,
    caption: 'reward points added — welcome to SHIELD',
  );
}

Future<void> _showEditConfirmation(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              width: 64,
              decoration: const BoxDecoration(
                color: AppColors.greenTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.brandGreenDeep,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Profile updated',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your details have been saved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textBody,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
