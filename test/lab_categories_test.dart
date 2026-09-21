import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/care_repository.dart';
import 'package:shield/module/labtest/lab_package.dart';
import 'package:shield/module/labtest/lab_test_screen.dart';
import 'package:shield/module/labtest/top_packages_screen.dart';

const _diabetes = LabCategory(id: '1', name: 'Diabetes', testCount: 7);
const _liver = LabCategory(
  id: '2',
  name: 'Liver Health',
  image: 'data:image/png;base64,not-really-base64',
  testCount: 5,
);

const _diabetesCheck = LabPackage(
  id: '10',
  name: 'Diabetes Check',
  categoryId: '1',
  testCount: 2,
  profileCount: 2,
  price: '500',
  mrp: '700',
);
const _liverPanel = LabPackage(
  id: '11',
  name: 'Liver Panel',
  categoryId: '2',
  testCount: 3,
  profileCount: 3,
  price: '900',
  mrp: '1,200',
);
const _uncategorised = LabPackage(
  id: '12',
  name: 'Full Body',
  testCount: 40,
  profileCount: 6,
  price: '999',
  mrp: '2,498',
);

/// "Explore by health concern": the category grid on the Lab landing screen,
/// and the filtered list a tile opens.
void main() {
  tearDown(() {
    CareRepository.labPackagesOverride = null;
    CareRepository.labCategoriesOverride = null;
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(400, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  group('the category grid', () {
    testWidgets('shows every active category with its name and test count', (
      tester,
    ) async {
      CareRepository.labPackagesOverride = () async => const [];
      CareRepository.labCategoriesOverride = () async => [_diabetes, _liver];

      await pump(tester, const LabTestScreen());

      expect(find.text('Explore by health concern'), findsOneWidget);
      expect(find.text('Diabetes'), findsOneWidget);
      expect(find.text('7 tests'), findsOneWidget);
      expect(find.text('Liver Health'), findsOneWidget);
      expect(find.text('5 tests'), findsOneWidget);
    });

    testWidgets('a category with no icon shows a plain fallback', (
      tester,
    ) async {
      // A package too, so the "Top Packages" strip below doesn't fall back to
      // its own science_outlined empty-state icon and confuse the count.
      CareRepository.labPackagesOverride = () async => const [_diabetesCheck];
      CareRepository.labCategoriesOverride = () async => const [_diabetes];

      await pump(tester, const LabTestScreen());

      expect(find.byIcon(Icons.science_outlined), findsOneWidget);
    });

    testWidgets('has nothing to show and hides the whole section', (
      tester,
    ) async {
      CareRepository.labPackagesOverride = () async => const [];
      CareRepository.labCategoriesOverride = () async => const [];

      await pump(tester, const LabTestScreen());

      expect(find.text('Explore by health concern'), findsNothing);
    });

    testWidgets('tapping a tile opens that category, named in the app bar', (
      tester,
    ) async {
      CareRepository.labPackagesOverride = () async => [
        _diabetesCheck,
        _liverPanel,
      ];
      CareRepository.labCategoriesOverride = () async => [_diabetes, _liver];

      await pump(tester, const LabTestScreen());

      await tester.tap(find.text('Diabetes'));
      await tester.pumpAndSettle();

      expect(find.text('Diabetes', skipOffstage: false), findsWidgets);
      expect(find.text('Diabetes Check'), findsOneWidget);
      expect(find.text('Liver Panel'), findsNothing);
    });
  });

  group('the filtered package list', () {
    testWidgets('shows only the packages filed under the given category', (
      tester,
    ) async {
      CareRepository.labPackagesOverride = () async => [
        _diabetesCheck,
        _liverPanel,
        _uncategorised,
      ];

      await pump(tester, const TopPackagesScreen(category: _diabetes));

      expect(find.text('Diabetes'), findsOneWidget); // the app-bar title
      expect(find.text('Diabetes Check'), findsOneWidget);
      expect(find.text('Liver Panel'), findsNothing);
      expect(find.text('Full Body'), findsNothing);
    });

    testWidgets('with no category shows every package, titled "All Packages"', (
      tester,
    ) async {
      CareRepository.labPackagesOverride = () async => [
        _diabetesCheck,
        _liverPanel,
        _uncategorised,
      ];

      await pump(tester, const TopPackagesScreen());

      expect(find.text('All Packages'), findsOneWidget);
      expect(find.text('Diabetes Check'), findsOneWidget);
      expect(find.text('Liver Panel'), findsOneWidget);
      expect(find.text('Full Body'), findsOneWidget);
    });

    testWidgets('a category with nothing in it shows the empty state', (
      tester,
    ) async {
      CareRepository.labPackagesOverride = () async => [_uncategorised];

      await pump(tester, const TopPackagesScreen(category: _diabetes));

      expect(find.text('No packages available right now'), findsOneWidget);
    });
  });
}
