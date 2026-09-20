import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/category_repository.dart';
import 'package:shield/module/categories/category_catalogue.dart';
import 'package:shield/module/home/category_section.dart';
import 'package:shield/theme/app_colors.dart';

/// A real 1×1 PNG — what `shieldweb` stores for an uploaded chip / tile image
/// (there a resized WebP/PNG data URI).
const _dataUri =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

const _live = [
  CategoryGroup(
    title: 'Vitamins & Supplements',
    tabLabel: 'Vitamins &\nSupplements',
    icon: Icons.medication_outlined,
    image: _dataUri,
    panelTint: AppColors.panelBlue,
    items: [
      SubCategory('Vitamin D', Icons.wb_sunny_outlined, image: _dataUri),
      SubCategory('Calcium', Icons.emoji_food_beverage_outlined),
    ],
  ),
];

void main() {
  setUp(CategoryCatalog.instance.reset);
  tearDown(CategoryCatalog.instance.reset);

  group('CategoryRepository row mapping', () {
    test('a sub-category keeps its uploaded image and offer', () {
      final sub = CategoryRepository.toSubCategory({
        'label': 'Skin Care',
        'iconName': 'face_retouching_natural_outlined',
        'image': _dataUri,
        'offer': 'Up to 40% off',
      });

      expect(sub.label, 'Skin Care');
      expect(sub.icon, Icons.face_retouching_natural_outlined);
      expect(sub.image, _dataUri);
      expect(sub.offer, 'Up to 40% off');
    });

    test('a sub-category with no image or offer falls back to icon and '
        'the default offer', () {
      final sub = CategoryRepository.toSubCategory({
        'label': 'Hair Care',
        'iconName': 'not_a_real_icon',
        'image': null,
        'offer': '',
      });

      expect(sub.image, isNull);
      expect(sub.icon, Icons.category_outlined);
      expect(sub.offer, 'Up to 50% off');
    });

    test('a category maps its chip image, banner, tint and tab label', () {
      final group = CategoryRepository.toCategoryGroup(
        {
          'title': 'Personal Care',
          'tabLabel': 'Personal\nCare',
          'iconName': 'spa_outlined',
          'image': _dataUri,
          'bannerImage': 'data:image/jpeg;base64,AAAA',
          'panelTint': 'panelGreen',
        },
        items: const [],
      );

      expect(group.title, 'Personal Care');
      expect(group.tabLabel, 'Personal\nCare');
      expect(group.image, _dataUri);
      expect(group.bannerImage, 'data:image/jpeg;base64,AAAA');
      expect(group.panelTint, AppColors.panelGreen);
    });

    test('a category with a blank tab label and image uses its title and '
        'no chip image', () {
      final group = CategoryRepository.toCategoryGroup(
        {'title': 'Surgicals', 'tabLabel': '', 'image': ''},
        items: const [],
      );

      expect(group.tabLabel, 'Surgicals');
      expect(group.image, isNull);
      expect(group.bannerImage, isNull);
      expect(group.panelTint, AppColors.pageTint);
    });
  });

  group('CategoryCatalog', () {
    test('serves the bundled seed until a backend copy arrives', () {
      expect(CategoryCatalog.instance.isFromBackend, isFalse);
      expect(CategoryCatalogue.groups.first.title, 'Personal Care');
    });

    test('swaps in the backend copy, and reset returns to the seed', () {
      CategoryCatalog.instance.useGroups(_live);

      expect(CategoryCatalog.instance.isFromBackend, isTrue);
      expect(CategoryCatalogue.groups.single.title, 'Vitamins & Supplements');

      CategoryCatalog.instance.reset();

      expect(CategoryCatalogue.groups.length, greaterThan(1));
    });

    test('the home strip skips a category an admin has retired instead of '
        'crashing', () {
      CategoryCatalog.instance.useGroups(_live);

      expect(
        CategoryCatalogue.shoppable.map((g) => g.title),
        ['Vitamins & Supplements'],
      );
    });
  });

  group('the home "Shop by categories" strip', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: CategorySection())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('draws an uploaded chip and tile image, and keeps the icon '
        'where none was uploaded', (tester) async {
      CategoryCatalog.instance.useGroups(_live);

      await pump(tester);

      final memoryImages = tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is MemoryImage);
      // The chip and the Vitamin D tile.
      expect(memoryImages.length, 2);
      expect(find.byIcon(Icons.wb_sunny_outlined), findsNothing);
      expect(find.byIcon(Icons.medication_outlined), findsNothing);
      // Calcium has no upload — it still shows its icon.
      expect(find.byIcon(Icons.emoji_food_beverage_outlined), findsOneWidget);
    });

    testWidgets('refreshes in place when the backend copy lands after the '
        'first paint', (tester) async {
      await pump(tester);
      expect(find.text('Personal\nCare'), findsOneWidget);

      CategoryCatalog.instance.useGroups(_live);
      await tester.pumpAndSettle();

      expect(find.text('Personal\nCare'), findsNothing);
      expect(find.text('Vitamin D'), findsOneWidget);
      expect(find.text('Calcium'), findsOneWidget);
    });
  });
}
