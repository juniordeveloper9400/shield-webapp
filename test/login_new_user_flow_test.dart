import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shield/module/auth/auth_service.dart';
import 'package:shield/module/auth/login_screen.dart';

import 'support/fake_auth_gateway.dart';

/// The sign-in screen opens on the mobile number alone. "Create account" (the
/// name field) only appears once the number is found to have no account, and a
/// number that already has one keeps its stored name whatever is typed.
void main() {
  /// Stands in for `app.users`: phone → stored name.
  late Map<String, String> members;
  late FakeAuthGateway gateway;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    members = {};
    gateway = FakeAuthGateway();
    AuthService.instance
      ..reset()
      ..useGateway(gateway)
      ..useMemberLookup(
        phoneExists: (phone) async => members.containsKey(phone),
        nameByPhone: (phone) async => members[phone],
      );
  });
  tearDown(() => AuthService.instance.reset());

  const phone = '9000012345';

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String hint, String value) async {
    await tester.enterText(find.widgetWithText(TextFormField, hint), value);
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  Future<void> tapGetOtp(WidgetTester tester) async {
    await tester.tap(find.text('Get OTP'));
    await settle(tester);
  }

  group('opening the screen', () {
    testWidgets('shows only the sign-in section', (tester) async {
      await pumpLogin(tester);

      expect(find.text('Sign in to Sahakar 360'), findsOneWidget);
      expect(find.text('Mobile number'), findsOneWidget);
      expect(find.text('Full name'), findsNothing);
      expect(find.text('Create account'), findsNothing);
      expect(find.text('Create an account'), findsNothing);
      expect(find.textContaining('New to Sahakar 360'), findsNothing);
      expect(find.textContaining('new user'), findsNothing);
    });
  });

  group('a number with no account', () {
    testWidgets('says the member is new and reveals the name field', (
      tester,
    ) async {
      await pumpLogin(tester);
      await fill(tester, '10-digit mobile number', phone);
      await tapGetOtp(tester);

      expect(find.textContaining("You're a new user"), findsOneWidget);
      expect(find.text('Create your Sahakar 360 account'), findsOneWidget);
      expect(find.text('Full name'), findsOneWidget);
      // Nothing was sent yet: the member still has to give a name.
      expect(gateway.codesSent, 0);
      expect(find.text('Verify your number'), findsNothing);
      // The number they typed is kept.
      expect(find.text(phone), findsOneWidget);
    });

    testWidgets('then sends the code with the typed name', (tester) async {
      await pumpLogin(tester);
      await fill(tester, '10-digit mobile number', phone);
      await tapGetOtp(tester);

      await fill(tester, 'Enter your name', 'Asha Nair');
      await tapGetOtp(tester);

      expect(find.text('Verify your number'), findsOneWidget);
      expect(AuthService.instance.pendingName, 'Asha Nair');

      expect(await AuthService.instance.verifyOtp(FakeAuthGateway.code), isNull);
      expect(AuthService.instance.currentUser.value?.name, 'Asha Nair');
    });

    testWidgets('“Back to sign in” returns to the number-only screen', (
      tester,
    ) async {
      await pumpLogin(tester);
      await fill(tester, '10-digit mobile number', phone);
      await tapGetOtp(tester);

      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to Sahakar 360'), findsOneWidget);
      expect(find.text('Full name'), findsNothing);
      expect(find.textContaining('new user'), findsNothing);
    });
  });

  group('a number that already has an account', () {
    testWidgets('signs in straight away, with no name asked', (tester) async {
      members[phone] = 'Asha Nair';
      await pumpLogin(tester);
      await fill(tester, '10-digit mobile number', phone);
      await tapGetOtp(tester);

      expect(find.text('Verify your number'), findsOneWidget);
      expect(find.text('Full name'), findsNothing);

      expect(await AuthService.instance.verifyOtp(FakeAuthGateway.code), isNull);
      expect(AuthService.instance.currentUser.value?.name, 'Asha Nair');
    });

    testWidgets(
      'reached from the create view with a new name, keeps the old name',
      (tester) async {
        await pumpLogin(tester);
        // Starts as a stranger's number, so the create view opens…
        await fill(tester, '10-digit mobile number', '9000099999');
        await tapGetOtp(tester);
        expect(find.text('Full name'), findsOneWidget);

        // …then the number is changed to an existing member's, with a new name.
        members[phone] = 'Asha Nair';
        await fill(tester, '10-digit mobile number', phone);
        await fill(tester, 'Enter your name', 'Somebody Else');
        await tapGetOtp(tester);

        expect(find.text('Verify your number'), findsOneWidget);
        expect(find.textContaining('saved name'), findsOneWidget);
        expect(AuthService.instance.pendingName, isEmpty);

        expect(await AuthService.instance.verifyOtp(FakeAuthGateway.code), isNull);
        expect(AuthService.instance.currentUser.value?.name, 'Asha Nair');
      },
    );
  });

  group('the service', () {
    test('an existing number keeps its stored name over a typed one', () async {
      members[phone] = 'Asha Nair';

      expect(
        await AuthService.instance.requestOtp(name: 'Somebody Else', phone: phone),
        isNull,
      );
      expect(await AuthService.instance.verifyOtp(FakeAuthGateway.code), isNull);

      expect(AuthService.instance.currentUser.value?.name, 'Asha Nair');
    });

    test('a new number takes the typed name', () async {
      expect(
        await AuthService.instance.requestOtp(name: 'Asha Nair', phone: phone),
        isNull,
      );
      expect(await AuthService.instance.verifyOtp(FakeAuthGateway.code), isNull);

      expect(AuthService.instance.currentUser.value?.name, 'Asha Nair');
    });

    test('with no stored or typed name it falls back to “Member”', () async {
      expect(await AuthService.instance.requestOtp(phone: phone), isNull);
      expect(await AuthService.instance.verifyOtp(FakeAuthGateway.code), isNull);

      expect(AuthService.instance.currentUser.value?.name, 'Member');
    });
  });
}
