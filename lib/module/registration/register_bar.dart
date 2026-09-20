import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'registration_flow.dart';
import 'registration_service.dart';

/// Sticky strip directly above the bottom navigation.
///
/// Only shown once the backend has said the member has not registered, offering
/// the reward — there is no dismiss here, because a nag that can be waved away
/// stops being a reminder. Once the member registers it disappears entirely
/// rather than swapping to a confirmation, freeing that slot back to just the
/// bottom nav; the saved profile itself is still shown (and editable) from the
/// Account tab.
///
/// It never guesses: while the registration is still being looked up, or when
/// the lookup could not be answered, a member who is in fact registered must
/// not be told to register — so the first shows nothing and the second says
/// plainly that the check failed, with a retry.
class RegisterBar extends StatelessWidget {
  const RegisterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RegistrationService.instance,
      builder: (context, _) {
        final service = RegistrationService.instance;
        if (service.isRegistered) {
          return const SizedBox.shrink();
        }
        switch (service.status) {
          case RegistrationStatus.notRegistered:
            return const _PromptStrip();
          case RegistrationStatus.unreachable:
            return const _RetryStrip();
          case RegistrationStatus.unknown:
          case RegistrationStatus.checking:
          case RegistrationStatus.registered:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

/// The registration could not be looked up (offline, the backend down): says so
/// instead of asking a possibly-registered member to register, and offers a
/// retry.
class _RetryStrip extends StatelessWidget {
  const _RetryStrip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandNavy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 18,
              color: AppColors.white,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Couldn’t check your registration',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () => RegistrationService.instance.retry(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.white,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Retry',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The backend says this member has not registered: the reward offer, pinned
/// until they actually register.
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
