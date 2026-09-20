import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Minimal in-memory [AuthGateway] — this tree has no shared
/// `test/support/fake_auth_gateway.dart` the way the root app does, and the
/// only thing these tests need is [deleteFirebaseUser]'s two outcomes.
class _FakeAuthGateway implements AuthGateway {
  bool refuseDelete = false;
  bool signOutCalled = false;

  @override
  Future<OtpError?> sendCode(String e164Phone) async => null;

  @override
  Future<OtpError?> confirmCode(String code) async => null;

  @override
  Future<AuthUser?> restoreUser() async => null;

  @override
  Future<void> saveDisplayName(String name) async {}

  @override
  void discard() {}

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  Future<String?> currentIdToken() async => null;

  @override
  Future<bool> deleteFirebaseUser() async => !refuseDelete;
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  setUp(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
  });
  tearDown(() {
    AuthService.instance.reset();
    AgentService.instance.reset();
  });

  group('AuthService.deleteAccount', () {
    test('ends the session and deletes the Firebase identity outright when '
        'Firebase allows it', () async {
      final auth = AuthService.instance;
      final gateway = _FakeAuthGateway();
      auth.useGateway(gateway);
      auth.signInAs();

      await auth.deleteAccount();

      expect(auth.isSignedIn, isFalse);
      expect(auth.hasPendingOtp, isFalse);
      expect(
        gateway.signOutCalled,
        isFalse,
        reason: 'deleteFirebaseUser succeeded — no fallback sign-out needed',
      );
    });

    test('still ends the session when Firebase refuses '
        '(requires-recent-login)', () async {
      final auth = AuthService.instance;
      final gateway = _FakeAuthGateway()..refuseDelete = true;
      auth.useGateway(gateway);
      auth.signInAs();

      await auth.deleteAccount();

      expect(
        auth.isSignedIn,
        isFalse,
        reason: 'the account is already gone in app.users regardless',
      );
      expect(gateway.signOutCalled, isTrue);
    });

    test('is a no-op with nobody signed in', () async {
      final auth = AuthService.instance;
      final gateway = _FakeAuthGateway();
      auth.useGateway(gateway);

      await auth.deleteAccount();

      expect(auth.isSignedIn, isFalse);
      expect(gateway.signOutCalled, isFalse);
    });
  });

  group('the account menu', () {
    testWidgets('offers Delete Account, below Log out', (tester) async {
      AuthService.instance.signInAs();

      await pump(tester, const AccountScreen());

      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('the confirm button stays off until DELETE is typed', (
      tester,
    ) async {
      AuthService.instance.signInAs();
      await pump(tester, const AccountScreen());

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
      await pump(tester, const AccountScreen());

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete your account?'), findsNothing);
      expect(AuthService.instance.isSignedIn, isTrue);
    });

    testWidgets('confirming deletes the account and the gate returns to '
        'login', (tester) async {
      AuthService.instance.useGateway(_FakeAuthGateway());
      AuthService.instance.signInAs();
      await pump(tester, const AccountScreen());

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

      await pump(tester, const AccountScreen());
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

      await pump(tester, const AccountScreen());
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
