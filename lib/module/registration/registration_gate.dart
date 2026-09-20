import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'registration_flow.dart';
import 'registration_service.dart';

/// The rule that only registered members can act: add to the cart, check out,
/// upload a prescription, book a lab test, buy a plan. Browsing is open to
/// everyone; anything that creates something on a member's behalf goes through
/// [ensure] first. The backend enforces the same rule on those requests
/// (`REGISTRATION_REQUIRED`) — this is the friendly half that explains it and
/// offers the form before a request is ever sent.
///
/// It never turns away a registered member by mistake: when the registration
/// hasn't been looked up yet (a refresh, a slow network) it waits for the
/// answer instead of guessing, and when the answer can't be had it says so
/// rather than sending the member to register again.
class RegistrationGate {
  const RegistrationGate._();

  /// True when the member may go ahead. [action] finishes the sentence "Only
  /// registered members can …" in the prompt — keep it short and lowercase.
  ///
  /// Otherwise explains, offers the registration form, and resolves true only
  /// if the member completes it.
  static Future<bool> ensure(
    BuildContext context, {
    String action = 'do this',
  }) async {
    final service = RegistrationService.instance;
    if (service.isRegistered) {
      return true;
    }

    // Not known yet: find out, showing that we are, rather than deciding
    // for the member.
    if (service.status != RegistrationStatus.notRegistered) {
      final status = await _resolveWithSpinner(context, service);
      if (!context.mounted) {
        return false;
      }
      if (service.isRegistered) {
        return true;
      }
      if (status == RegistrationStatus.unreachable ||
          status == RegistrationStatus.unknown) {
        _say(
          context,
          'We couldn’t check your registration. Check your connection and '
          'try again.',
        );
        return false;
      }
    }

    // The backend has said: not registered.
    final register = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Register to continue'),
        content: Text(
          'Only registered members can $action. It takes a minute, and you '
          'earn ${RegistrationService.rewardPoints} reward points.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
            child: const Text('Register now'),
          ),
        ],
      ),
    );
    if (register != true || !context.mounted) {
      return false;
    }

    final done = await RegistrationFlow.show(context);
    return done && service.isRegistered;
  }

  /// Waits for the registration to be looked up, with a spinner over the app if
  /// it takes more than a moment. The short delay keeps the common case — the
  /// answer is already there — free of a flash.
  static Future<RegistrationStatus> _resolveWithSpinner(
    BuildContext context,
    RegistrationService service,
  ) async {
    final resolving = service.ensureResolved();
    var settled = false;
    final result = resolving.whenComplete(() => settled = true);

    await Future.any<void>([
      result,
      Future<void>.delayed(const Duration(milliseconds: 350)),
    ]);
    if (settled || !context.mounted) {
      return result;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    final status = await result;
    if (navigator.canPop()) {
      navigator.pop();
    }
    return status;
  }

  static void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => RegistrationService.instance.retry(),
          ),
        ),
      );
  }
}
