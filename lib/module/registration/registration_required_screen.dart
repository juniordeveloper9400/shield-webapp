import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// What a screen shows in place of its real content while the signed-in
/// member's own Sahakar 360 registration isn't complete yet — anywhere a flow's
/// eventual submit is refused server-side until that's true (agent requests,
/// so far), there is no point showing the real form at all: better to say so
/// up front than let someone fill a whole flow in for a submit that can only
/// fail. [title] names the flow this is standing in for.
class RegistrationRequiredScreen extends StatelessWidget {
  final String title;
  final VoidCallback onComplete;

  const RegistrationRequiredScreen({
    super.key,
    required this.title,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.badge_outlined,
                size: 56,
                color: AppColors.brandBlue,
              ),
              const SizedBox(height: 18),
              const Text(
                'Complete your registration first',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Sahakar 360 needs your registration finished — name and store — "
                'before this can be submitted. Complete it, then come back '
                'to this screen.',
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
                  onPressed: onComplete,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Complete registration',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
