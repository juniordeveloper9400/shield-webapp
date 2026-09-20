import 'dart:async';

import 'package:flutter/material.dart';

import '../registration/registration_gate.dart';
import 'auth_service.dart';
import 'login_screen.dart';

/// Entry points into the sign-in flow.
///
/// The app is gated at launch, so in normal use these never fire — every
/// screen below the gate already has a session. They stay as the backstop for
/// the money-moving actions, which must not run against an empty session if a
/// route is ever reached another way.
class AuthFlow {
  const AuthFlow._();

  /// Pushes the login screen over the app and resolves to whether a member is
  /// signed in once it closes.
  static Future<bool> show(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LoginScreen(),
      ),
    );
    return AuthService.instance.isSignedIn;
  }

  /// Runs [action] when signed in, otherwise opens the login screen first and
  /// only proceeds if the member completed it.
  static Future<void> guard(
    BuildContext context,
    FutureOr<void> Function() action,
  ) async {
    if (AuthService.instance.isSignedIn) {
      await action();
      return;
    }

    final signedIn = await show(context);
    if (signedIn && context.mounted) {
      await action();
    }
  }

  /// Like [guard], and then also requires a completed registration — for the
  /// actions only registered members may take (checkout, booking, uploading a
  /// prescription, buying a plan). An unregistered member is told why and
  /// offered the form; [action] only runs if they finish it. [reason] finishes
  /// the sentence "Only registered members can …".
  static Future<void> guardRegistered(
    BuildContext context,
    String reason,
    FutureOr<void> Function() action,
  ) {
    return guard(context, () async {
      if (!context.mounted) {
        return;
      }
      if (await RegistrationGate.ensure(context, action: reason) &&
          context.mounted) {
        await action();
      }
    });
  }
}
