import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/care_repository.dart';
import 'package:shield/module/labtest/lab_cart_service.dart';
import 'package:shield/module/labtest/lab_package.dart';
import 'package:shield/module/labtest/lab_test_screen.dart';

LabPackage _profile(
  int n, {
  String? name,
  String price = '309',
  String mrp = '500',
  int tests = 2,
}) => LabPackage(
  id: '$n',
  name: name ?? 'Profile $n',
  isProfile: true,
  testCount: tests,
  profileCount: 1,
  price: price,
  mrp: mrp,
);

/// "Most Common Tests": the banner strip of single tests sitting right under
/// the search bar, above the package cards — the same single-test data
/// "Top Profiles and Tests" lists further down, just the first few of them
/// shown as a quick-add shelf.
void main() {
  setUp(LabCartService.instance.reset);
  tearDown(() {
    LabCartService.instance.reset();
    CareRepository.labPackagesOverride = null;
    CareRepository.labCategoriesOverride = null;
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(400, 2600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('shows up to six single tests as a banner strip above the '
      'package cards', (tester) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => [
      for (var i = 1; i <= 8; i++) _profile(i, name: 'Test number $i'),
    ];

    // Wide enough that all six banner cards lay out without needing a
    // horizontal scroll — the strip is a lazily-built ListView, so an
    // offscreen card simply isn't there to find yet.
    await pump(
      tester,
      const LabTestScreen(),
      size: const Size(1400, 2600),
    );

    expect(find.text('Most Common Tests'), findsOneWidget);
    // The first five lead "Top Profiles and Tests" too, so they're on both
    // shelves; the sixth is banner-only, and the rest are left to "View all".
    expect(find.text('Test number 1'), findsNWidgets(2));
    expect(find.text('Test number 5'), findsNWidgets(2));
    expect(find.text('Test number 6'), findsOneWidget);
    expect(find.text('Test number 7'), findsNothing);
    expect(find.text('Test number 8'), findsNothing);
  });

  testWidgets('with no single tests on offer, the banner does not render', (
    tester,
  ) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => const [
      LabPackage(
        id: '100',
        name: 'Preventive Plus',
        testCount: 83,
        profileCount: 9,
        price: '999',
        mrp: '2,500',
      ),
    ];

    await pump(tester, const LabTestScreen());

    expect(find.text('Most Common Tests'), findsNothing);
  });

  testWidgets('the + books it for the chosen patients, then shows a tick — '
      'the same basket "Top Profiles and Tests" reads', (tester) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => [_profile(1, name: 'HbA1c')];

    await pump(tester, const LabTestScreen());

    await tester.ensureVisible(find.byKey(const ValueKey('add-common-1')));
    await tester.tap(find.byKey(const ValueKey('add-common-1')));
    await tester.pumpAndSettle();

    expect(find.text('Select number of patients'), findsOneWidget);
    await tester.tap(find.text('2 patients'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add · ₹'));
    await tester.pumpAndSettle();

    expect(LabCartService.instance.bookingCount, 1);
    expect(LabCartService.instance.bookings.first.package.name, 'HbA1c');
    expect(LabCartService.instance.bookings.first.patients, 2);
    // Both the banner card's own button and the matching row further down in
    // "Top Profiles and Tests" now read the same booked state.
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
  });
}
