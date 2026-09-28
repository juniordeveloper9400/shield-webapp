import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/account/account_screen.dart';
import 'package:shield/module/account/settings_screen.dart';
import 'package:shield/module/auth/auth_service.dart';

/// Help & Support, Privacy Policy, Terms & Conditions and Delete Account
/// all used to sit directly on the account menu; they moved under Settings.
/// The dedicated tests for each of those (delete_account_test.dart) cover
/// reaching them through here already — this file is just about Settings
/// itself: that it exists, groups them the way the old account menu did,
/// and that Log out stayed put rather than moving too.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  setUp(() => AuthService.instance.reset());
  tearDown(() => AuthService.instance.reset());

  testWidgets('Log out stays on the account menu — only the rest moved', (
    tester,
  ) async {
    AuthService.instance.signInAs();
    await pump(tester, const AccountScreen());

    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
    'Settings groups Help & Support, Privacy Policy and Terms & Conditions together, Delete Account on its own',
    (tester) async {
      await pump(tester, const SettingsScreen());

      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
      // Neither Log out nor anything from the main account menu bled in here.
      expect(find.text('Log out'), findsNothing);
      expect(find.text('My Wallet'), findsNothing);
    },
  );

  testWidgets('tapping Settings from the account menu opens it', (tester) async {
    AuthService.instance.signInAs();
    await pump(tester, const AccountScreen());

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
