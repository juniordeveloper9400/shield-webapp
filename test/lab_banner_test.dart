import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/care_repository.dart';
import 'package:shield/module/home/home_hero_banner.dart';
import 'package:shield/module/labtest/lab_test_screen.dart';

/// The Lab section's own promotional strip (migration 0069) — the same
/// [HomeHeroBanner] widget the home screen uses, pointed at the `'lab'`
/// placement instead, with no bundled fallback image.
void main() {
  tearDown(() {
    CareRepository.labPackagesOverride = null;
    CareRepository.labCategoriesOverride = null;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LabTestScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('reads the Lab placement, with no bundled fallback', (
    tester,
  ) async {
    CareRepository.labCategoriesOverride = () async => const [];
    CareRepository.labPackagesOverride = () async => const [];

    await pump(tester);

    final banner = tester.widget<HomeHeroBanner>(find.byType(HomeHeroBanner));
    expect(banner.placement, 'lab');
    expect(banner.showBundledDefault, isFalse);
  });

  testWidgets(
    'with no banner configured (no backend/Neon in a test run), the strip '
    "takes up no space — it doesn't fall back to Home's default image",
    (tester) async {
      CareRepository.labCategoriesOverride = () async => const [];
      CareRepository.labPackagesOverride = () async => const [];

      await pump(tester);

      // The widget is still in the tree (wired up), but renders to nothing:
      // no default-banner image asset, no placeholder icon for a broken one.
      expect(find.byType(HomeHeroBanner), findsOneWidget);
      expect(find.image(const AssetImage(HomeHeroBanner.assetPath)), findsNothing);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
    },
  );
}
