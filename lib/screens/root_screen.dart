import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../module/auth/auth_service.dart';
import '../module/auth/login_screen.dart';
import '../module/persona/persona_service.dart';
import 'app_shell.dart';
import 'splash_screen.dart';
import 'web_access_screen.dart';

/// App entry point: the splash, then the sign-in gate, then the shell.
///
/// The gate is a gate, not an offer — nothing below it is reachable without a
/// session. Because it is driven by [AuthService.currentUser] rather than a
/// pushed route, signing out anywhere in the app drops straight back to it.
class RootScreen extends StatefulWidget {
  /// How long the splash stays up.
  final Duration splashDuration;

  const RootScreen({
    super.key,
    this.splashDuration = const Duration(milliseconds: 1600),
  });

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  Timer? _timer;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer(widget.splashDuration, () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A member the admin converts while the app is open should land on the web
    // notice on the next foreground, not keep browsing as a customer.
    if (state == AppLifecycleState.resumed) {
      PersonaService.instance.refreshCurrent();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return const SplashScreen();
    }

    return ValueListenableBuilder<AuthUser?>(
      valueListenable: AuthService.instance.currentUser,
      builder: (context, user, _) {
        if (user == null) {
          return const LoginScreen();
        }
        // A converted member (admin made them an agent / investor) is sent to
        // the web console on the APK; on the web build they keep the full app
        // and get their agent / investor card on the home screen.
        return ListenableBuilder(
          listenable: PersonaService.instance,
          builder: (context, _) {
            if (!kIsWeb && PersonaService.instance.isConverted) {
              return const WebAccessScreen();
            }
            // Keyed on the session so signing out clears the previous member's
            // tab and scroll state instead of carrying it over to the next.
            return AppShell(key: ValueKey(user.phone));
          },
        );
      },
    );
  }
}
