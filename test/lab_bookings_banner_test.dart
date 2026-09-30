import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/care_repository.dart';
import 'package:shield/module/labtest/lab_test_screen.dart';
import 'package:shield/module/labtest/my_lab_bookings_screen.dart';

/// The "My Lab Bookings & Reports" banner on the Lab landing screen — a
/// direct way into a member's own lab reports without going through
/// Account first.
void main() {
  tearDown(() {
    CareRepository.labPackagesOverride = null;
    CareRepository.labCategoriesOverride = null;
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('offers a way into My Lab Bookings & Reports', (tester) async {
    CareRepository.labPackagesOverride = () async => const [];
    CareRepository.labCategoriesOverride = () async => const [];

    await pump(tester, const LabTestScreen());

    expect(find.text('My Lab Bookings & Reports'), findsOneWidget);

    await tester.tap(find.text('My Lab Bookings & Reports'));
    await tester.pumpAndSettle();

    expect(find.byType(MyLabBookingsScreen), findsOneWidget);
  });
}
