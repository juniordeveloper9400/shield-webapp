import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shield/module/account/account_screen.dart';
import 'package:shield/module/agent/agent_service.dart';
import 'package:shield/module/auth/auth_service.dart';

class _RecordingOpener {
  Uri? opened;
  bool result = true;

  Future<bool> call(Uri uri) async {
    opened = uri;
    return result;
  }
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  /// Opens the account menu, then taps through to Settings — where Delete
  /// Account, Privacy Policy and Terms & Conditions all actually live now.
  Future<void> pumpToSettings(WidgetTester tester) async {
    await pump(tester, const AccountScreen());
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    // deleteAccount now ends with BackendSession.signOut(), which persists
    // the cleared session via shared_preferences — needs a mock channel or
    // the call hangs waiting on a real platform channel.
    SharedPreferences.setMockInitialValues({});
    AuthService.instance.reset();
    AgentService.instance.reset();
  });
  tearDown(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
  });

  group('AuthService.deleteAccount', () {
    test('ends the session', () async {
      final auth = AuthService.instance;
      auth.signInAs();

      await auth.deleteAccount();

      expect(auth.isSignedIn, isFalse);
      expect(auth.hasPendingOtp, isFalse);
    });

    test('is a no-op with nobody signed in', () async {
      final auth = AuthService.instance;

      await auth.deleteAccount();

      expect(auth.isSignedIn, isFalse);
    });
  });

  group('the account menu', () {
    testWidgets('offers Settings, not Delete Account directly', (tester) async {
      AuthService.instance.signInAs();

      await pump(tester, const AccountScreen());

      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Delete Account'), findsNothing);
    });

    testWidgets('Settings offers Delete Account', (tester) async {
      AuthService.instance.signInAs();
      await pumpToSettings(tester);

      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('the confirm button stays off until DELETE is typed', (
      tester,
    ) async {
      AuthService.instance.signInAs();
      await pumpToSettings(tester);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your account?'), findsOneWidget);
      Finder confirmButton() => find.widgetWithText(TextButton, 'Delete Account');
      expect(tester.widget<TextButton>(confirmButton()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delete');
      await tester.pump();
      expect(
        tester.widget<TextButton>(confirmButton()).onPressed,
        isNotNull,
        reason: 'the check is case-insensitive',
      );
    });

    testWidgets('cancel closes the dialog and leaves the account untouched', (
      tester,
    ) async {
      AuthService.instance.signInAs();
      await pumpToSettings(tester);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your account?'), findsNothing);
      expect(AuthService.instance.isSignedIn, isTrue);
    });

    testWidgets('confirming deletes the account and the gate returns to '
        'login', (tester) async {
      AuthService.instance.signInAs();
      await pumpToSettings(tester);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your account?'), findsNothing);
      expect(AuthService.instance.isSignedIn, isFalse);
    });

    testWidgets('Privacy Policy opens the public policy page', (
      tester,
    ) async {
      AuthService.instance.signInAs();
      final original = privacyPolicyOpener;
      final recorder = _RecordingOpener();
      privacyPolicyOpener = recorder.call;
      addTearDown(() => privacyPolicyOpener = original);

      await pumpToSettings(tester);
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(recorder.opened, Uri.parse(privacyPolicyUrl));
    });

    testWidgets('Terms & Conditions opens the public terms page', (
      tester,
    ) async {
      AuthService.instance.signInAs();
      final original = termsOpener;
      final recorder = _RecordingOpener();
      termsOpener = recorder.call;
      addTearDown(() => termsOpener = original);

      await pumpToSettings(tester);
      await tester.tap(find.text('Terms & Conditions'));
      await tester.pumpAndSettle();

      expect(recorder.opened, Uri.parse(termsUrl));
    });

    testWidgets(
      'offers "Become a Sahakar 360 Agent" to a member who is not one, not "Agent Portal"',
      (tester) async {
        AuthService.instance.signInAs(phone: '9000000099');

        await pump(tester, const AccountScreen());

        expect(find.text('Become a Sahakar 360 Agent'), findsOneWidget);
        expect(find.text('Agent Portal'), findsNothing);
      },
    );
  });
}
