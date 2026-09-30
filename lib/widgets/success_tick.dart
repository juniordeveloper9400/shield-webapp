import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The green disc and tick, popped in with a short scale so a confirmation
/// screen reads as one the moment it lands — the product order-placed screen
/// and the lab booking-placed screen share this exact animation so "you're
/// done" looks and feels the same everywhere in the app.
class SuccessTick extends StatelessWidget {
  const SuccessTick({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: AppColors.greenTint,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.brandGreen, width: 2),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 46,
          color: AppColors.brandGreenDeep,
        ),
      ),
    );
  }
}
