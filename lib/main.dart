import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'data/backend/backend_http.dart';
import 'data/neon/neon_http.dart';
import 'firebase_options.dart';
import 'module/auth/auth_service.dart';
import 'module/agent/agent_geo.dart';
import 'module/catalogue/catalogue_service.dart';
import 'module/categories/category_catalogue.dart';
import 'module/home/customer_reviews_service.dart';
import 'module/orders/purchase_service.dart';
import 'module/persona/persona_service.dart';
import 'module/refer/referral_service.dart';
import 'module/rewards/rewards_service.dart';
import 'screens/root_screen.dart';
import 'theme/app_colors.dart';
import 'widgets/app_messenger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash and error reporting. Safe to call unconditionally — the SDK's own
  // documented behavior is to stay disabled when `dsn` is empty, the same
  // "no-op until configured" contract every other optional integration in
  // this app already follows (BackendHttp, NeonHttp, Firebase). Build with
  // --dart-define=SENTRY_DSN=... to turn it on; see docs/sentry.md.
  await SentryFlutter.init((options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN');
    options.environment = const String.fromEnvironment(
      'SENTRY_ENVIRONMENT',
      defaultValue: 'production',
    );
    // Off by default — see backend/api's instrument.ts for the same choice
    // and why: performance tracing counts separately against a Sentry
    // plan's event quota from error events.
    options.tracesSampleRate = 0;
  });

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

  // Follow the session for an admin-granted persona: a member converted to an
  // agent / investor gets their portal card on the web build, and is sent to
  // the web console on the APK. Reloads on sign-in, sign-out and app resume.
  PersonaService.instance.attach();

  // Follow the session for the reward-points balance: load the ledger on
  // sign-in, clear it on sign-out. The header coin, rewards screen and menu
  // read RewardsService.balance from here.
  RewardsService.instance.attach();

  // Follow the session for the refer-and-earn standing: load it on sign-in,
  // clear it on sign-out. The home card and the refer & earn screen both
  // read ReferralService.progress / .code.
  ReferralService.instance.attach();

  // Follow the session for the member's real order history: load it from
  // app."order" on sign-in, clear it on sign-out. The "Your savings" card and
  // the Orders tab both read PurchaseService from here.
  PurchaseService.instance.attach();

  // Warm the storefront catalogue so the home rows have products on first
  // paint rather than popping in a beat later. Fire-and-forget — the home,
  // category and search screens each call ensureLoaded() again and share this
  // one request.
  unawaited(CatalogueService.instance.ensureLoaded());

  // Warm the category catalogue the same way, so "Shop by categories" draws the
  // admin's own chip and tile images on first paint rather than the bundled
  // seed flashing up first.
  unawaited(CategoryCatalog.instance.ensureLoaded());

  // Warm "What our customers have to say" the same way, so the reel shows
  // the admin's own clips on first paint rather than the bundled fallback
  // flashing up first.
  unawaited(CustomerReviewsService.instance.ensureLoaded());

  // Warm the agent geographic hierarchy (regions … wards) so "My Team" and
  // the agent registration form draw the database copy, not the bundled seed.
  unawaited(AgentGeo.instance.ensureLoaded());

  // Keep the backend's Vercel functions and Neon database from suspending
  // while this app is open — see BackendHttp.keepWarm's own doc for why
  // this exists instead of relying solely on the repo's GitHub Actions cron.
  BackendHttp.instance.keepWarm();

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
      title: 'Sahakar 360',
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
