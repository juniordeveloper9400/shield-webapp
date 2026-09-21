import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/care_repository.dart';
import 'package:shield/module/labtest/lab_cart_service.dart';
import 'package:shield/module/labtest/lab_package.dart';
import 'package:shield/module/labtest/lab_test_screen.dart';
import 'package:shield/module/labtest/top_packages_screen.dart';

LabPackage _profile(
  int n, {
  String? name,
  String price = '309',
  String mrp = '500',
  int tests = 2,
  String categoryId = '',
}) => LabPackage(
  id: '$n',
  name: name ?? 'Profile $n',
  categoryId: categoryId,
  isProfile: true,
  testCount: tests,
  profileCount: 1,
  price: price,
  mrp: mrp,
);

const _package = LabPackage(
  id: '100',
  name: 'Preventive Plus',
  testCount: 83,
  profileCount: 9,
  price: '999',
  mrp: '2,500',
);

/// "Top Profiles and Tests": the single tests and group tests a lab switched on
/// with "Show in the app", listed as bookable rows beside the package cards.
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

  testWidgets('lists a listed test with its price, saving and test count', (
    tester,
  ) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => [
      _package,
      _profile(1, name: 'HbA1c'),
      _profile(
        2,
        name: 'Liver Function Test',
        price: '359',
        mrp: '899',
        tests: 12,
      ),
    ];

    await pump(tester, const LabTestScreen());

    expect(find.text('Top Profiles and Tests'), findsOneWidget);
    expect(find.text('HbA1c'), findsOneWidget);
    expect(find.text('₹309'), findsOneWidget);
    expect(find.text('₹500'), findsOneWidget);
    expect(find.text('38.20% OFF'), findsOneWidget);
    expect(find.text('· 2 tests'), findsOneWidget);
    expect(find.text('Liver Function Test'), findsOneWidget);
    expect(find.text('· 12 tests'), findsOneWidget);
    // Five or fewer: nothing more to open.
    expect(find.byKey(const ValueKey('view-all-profiles')), findsNothing);
  });

  testWidgets('a one-test listing is not a package card', (tester) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => [
      _package,
      _profile(1, name: 'HbA1c'),
    ];

    await pump(tester, const LabTestScreen());

    // The strip carries the real package only; HbA1c is a row, not a card.
    expect(find.text('Preventive Plus'), findsOneWidget);
    expect(find.text('Top Packages'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
  });

  testWidgets('with only tests on offer there is no empty package strip', (
    tester,
  ) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => [_profile(1)];

    await pump(tester, const LabTestScreen());

    expect(find.text('Top Packages'), findsNothing);
    expect(find.text('No packages available right now'), findsNothing);
    expect(find.text('Top Profiles and Tests'), findsOneWidget);
  });

  testWidgets('with nothing at all it still says so', (tester) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => const [];

    await pump(tester, const LabTestScreen());

    expect(find.text('No packages available right now'), findsOneWidget);
    expect(find.text('Top Profiles and Tests'), findsNothing);
  });

  testWidgets('shows five, and "View all N tests" opens the rest', (
    tester,
  ) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => [
      for (var i = 1; i <= 7; i++) _profile(i, name: 'Test number $i'),
    ];

    await pump(tester, const LabTestScreen());

    expect(find.text('Test number 5'), findsOneWidget);
    expect(find.text('Test number 6'), findsNothing);
    expect(find.text('View all 7 tests ›'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('view-all-profiles')));
    await tester.tap(find.byKey(const ValueKey('view-all-profiles')));
    await tester.pumpAndSettle();

    expect(find.text('Top Profiles and Tests'), findsOneWidget); // app bar
    expect(find.text('Test number 6'), findsOneWidget);
    expect(find.text('Test number 7'), findsOneWidget);
  });

  testWidgets('the + books it for the chosen patients, then shows a tick', (
    tester,
  ) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => [
      _package,
      _profile(1, name: 'HbA1c'),
    ];

    await pump(tester, const LabTestScreen());

    await tester.ensureVisible(find.byKey(const ValueKey('add-profile-1')));
    await tester.tap(find.byKey(const ValueKey('add-profile-1')));
    await tester.pumpAndSettle();

    expect(find.text('Select number of patients'), findsOneWidget);
    await tester.tap(find.text('2 patients'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add · ₹'));
    await tester.pumpAndSettle();

    expect(LabCartService.instance.bookingCount, 1);
    expect(LabCartService.instance.bookings.first.package.name, 'HbA1c');
    expect(LabCartService.instance.bookings.first.patients, 2);
    expect(LabCartService.instance.subtotal, 618);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('a test wears the icon of its category', (tester) async {
    CareRepository.labCategoriesOverride = () async => const [
      LabCategory(id: '7', name: 'Diabetes', testCount: 1),
    ];
    CareRepository.labPackagesOverride = () async => [
      _package,
      _profile(1, name: 'HbA1c', categoryId: '7'),
    ];

    await pump(tester, const LabTestScreen());

    // No uploaded image on the category: the plain lab icon stands in — one
    // for the category tile and one for the test row.
    expect(find.byIcon(Icons.science_outlined), findsNWidgets(2));
  });

  testWidgets('All Packages leaves single tests out; a category shows both', (
    tester,
  ) async {
    CareRepository.labPackagesOverride = () async => [
      const LabPackage(
        id: '100',
        name: 'Diabetes Check',
        categoryId: '7',
        testCount: 4,
        profileCount: 2,
        price: '999',
        mrp: '1,500',
      ),
      _profile(1, name: 'HbA1c', categoryId: '7'),
      _profile(2, name: 'Stray Test'),
    ];

    await pump(tester, const TopPackagesScreen());
    expect(find.text('Diabetes Check'), findsOneWidget);
    expect(find.text('HbA1c'), findsNothing);
    expect(find.text('Stray Test'), findsNothing);

    await pump(
      tester,
      const TopPackagesScreen(
        category: LabCategory(id: '7', name: 'Diabetes', testCount: 2),
      ),
    );
    expect(find.text('Diabetes Check'), findsOneWidget);
    expect(find.text('HbA1c'), findsOneWidget);
    expect(find.text('Stray Test'), findsNothing);
  });
}
