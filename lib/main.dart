import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/neon/neon_http.dart';
import 'firebase_options.dart';
import 'module/auth/auth_service.dart';
import 'module/catalogue/catalogue_service.dart';
import 'screens/root_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/app_messenger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Member sign-in is Firebase Phone Auth with no demo or offline fallback.
  // Bring Firebase up before the app starts; if the current platform has no
  // configured options (only Android is wired today — see FIREBASE_SETUP.md)
  // the app still starts so the UI is reachable, and the sign-in step reports
  // that verification is unavailable instead of white-screening here.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error, stack) {
    debugPrint('Firebase init failed — member sign-in will be unavailable: '
        '$error');
    debugPrintStack(stackTrace: stack);
  }

  // Bring back a member who has signed in before, so they land in the app
  // rather than on the login screen. Best-effort — a failure here must not
  // hold up launch.
  try {
    await AuthService.instance.restoreSession();
  } catch (error) {
    debugPrint('restoreSession failed — starting signed out: $error');
  }

  // Warm the storefront catalogue so the home rows have products on first
  // paint rather than popping in a beat later. Fire-and-forget — the home,
  // category and search screens each call ensureLoaded() again and share this
  // one request.
  unawaited(CatalogueService.instance.ensureLoaded());

  // One line at launch — via dart:developer so it survives a release build —
  // saying whether the Neon write-through is live. A build started without
  // --dart-define-from-file=.env leaves every member write a silent no-op, and
  // that used to look like data that just never saved.
  if (!NeonHttp.isConfigured) {
    NeonHttp.log('DATABASE_URL not set at build time — sign-in / registration '
        'will not be saved. Build with --dart-define-from-file=.env');
  } else {
    NeonHttp.instance.ping().then(
          (_) => NeonHttp.log('connected — sign-in / registration will save'),
          onError: (Object e) =>
              NeonHttp.log('endpoint unreachable — writes will be dropped',
                  error: e),
        );
  }

  runApp(const ShieldApp());
}

class ShieldApp extends StatelessWidget {
  const ShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SHIELD',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brandBlue,
          primary: AppColors.brandBlue,
        ),
        splashFactory: InkRipple.splashFactory,
      ),
      home: const RootScreen(),
    );
  }
}
