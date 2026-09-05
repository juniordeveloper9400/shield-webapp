import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'registration_flow.dart';
import 'registration_service.dart';

/// Sticky strip directly above the bottom navigation.
///
/// Before registration it offers the reward and stays put — there is no
/// dismiss here, because a nag that can be waved away stops being a
/// reminder. After registration it swaps to showing the member's own saved
/// details instead of disappearing, and both are pinned: [RegistrationService]
/// restores the profile from Neon on sign-in, so minimising the app, or
/// signing out and back in on the same account, brings the same strip back
/// rather than losing it to whatever this process happens to have in memory.
class RegisterBar extends StatelessWidget {
  const RegisterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RegistrationService.instance,
      builder: (context, _) {
        final profile = RegistrationService.instance.profile;
        if (profile != null) {
          return _RegisteredStrip(profile: profile);
        }
        return const _PromptStrip();
      },
    );
  }
}

/// Before registration: the reward offer, pinned until the member actually
/// registers.
class _PromptStrip extends StatelessWidget {
  const _PromptStrip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandGreenDark,
      child: InkWell(
        onTap: () => RegistrationFlow.show(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.stars_rounded,
                  size: 16,
                  color: AppColors.brandGreenDark,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Register now & get '
                  '${RegistrationService.rewardPoints} reward points',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => RegistrationFlow.show(context),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Register',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
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

/// After registration: the member's own saved details, in the same slot the
/// prompt used to occupy — tapping it opens the form again to edit rather
/// than to register.
class _RegisteredStrip extends StatelessWidget {
  const _RegisteredStrip({required this.profile});

  final Registration profile;

  @override
  Widget build(BuildContext context) {
    final store = profile.store;
    return Material(
      color: AppColors.brandGreenDark,
      child: InkWell(
        onTap: () => RegistrationFlow.show(context, isEditing: true),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: AppColors.brandGreenDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registered · ${profile.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      store != null ? store.name : profile.addressLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
