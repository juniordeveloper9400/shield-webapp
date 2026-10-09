import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/product_repository.dart';
import 'package:shield/module/cart/cart_service.dart';
import 'package:shield/module/home/product_showcase.dart';
import 'package:shield/module/product/product_detail_content.dart';
import 'package:shield/module/product/product_detail_screen.dart';

/// The Product Details page shows admin-entered content only — see the
/// identical fix in the root app's `test/product_detail_test.dart`. Here the
/// content comes from `backend/api` (`GET /v1/public/catalogue/products/:id`),
/// keyed by [Product.backendId], not the direct-Neon path root uses.
void main() {
  setUp(CartService.instance.reset);
  tearDown(() {
    CartService.instance.reset();
    ProductRepository.detailOverride = null;
  });

  const dolo = Product(
    name: 'Dolo 650mg Tablet',
    pack: 'Strip of 15 tablets',
    price: '32',
    mrp: '40',
    discountLabel: '20% OFF',
    icon: Icons.medication_outlined,
  );

  const doloWithId = Product(
    name: 'Dolo 650mg Tablet',
    pack: 'Strip of 15 tablets',
    price: '32',
    mrp: '40',
    discountLabel: '20% OFF',
    icon: Icons.medication_outlined,
    backendId: 501,
  );

  const adminContent = ProductDetailData(
    description: 'A fever and pain reliever dosed for adults.',
    storage: 'Store below 25°C, away from moisture.',
    highlights: ['Fast-acting', 'No prescription needed'],
    benefits: ['Brings down fever', 'Eases body pain'],
    faqs: [ProductFaq('Can I take this with food?', 'Yes, with or without food.')],
  );

  Future<void> pumpDetail(
    WidgetTester tester,
    Product product, {
    Size size = const Size(430, 2600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(product: product)),
    );
    await tester.pumpAndSettle();
  }

  group('with no backend id (never synced) or no detail added', () {
    testWidgets('shows the header, price and ADD, and no admin sections', (
      tester,
    ) async {
      await pumpDetail(tester, dolo);

      expect(find.text('Dolo 650mg Tablet'), findsWidgets);
      expect(find.text('₹32'), findsWidgets);
      expect(find.text('ADD'), findsWidgets);

      expect(find.byIcon(Icons.ac_unit_rounded), findsNothing);
      expect(find.text('Product highlights'), findsNothing);
      expect(find.text('Product description'), findsNothing);
      expect(find.text('Key benefits'), findsNothing);
      expect(find.text('Frequently asked questions'), findsNothing);
    });

    testWidgets('a product with a backend id but nothing added still shows '
        'no admin sections', (tester) async {
      ProductRepository.detailOverride = (id) async {
        expect(id, 501);
        return null;
      };

      await pumpDetail(tester, doloWithId);

      expect(find.text('Product highlights'), findsNothing);
      expect(find.text('Frequently asked questions'), findsNothing);
    });
  });

  group('with admin-entered content', () {
    testWidgets('shows exactly the sections the admin filled in', (
      tester,
    ) async {
      ProductRepository.detailOverride = (_) async => adminContent;

      await pumpDetail(tester, doloWithId);

      expect(find.byIcon(Icons.ac_unit_rounded), findsOneWidget);
      expect(find.text(adminContent.storage), findsOneWidget);
      expect(find.text('Product highlights'), findsOneWidget);
      expect(find.text('Fast-acting'), findsOneWidget);
      expect(find.text('Key benefits'), findsOneWidget);
      expect(find.text('Frequently asked questions'), findsOneWidget);
      // Left blank by the admin — no section for it.
      expect(find.text('Directions for use'), findsNothing);
      expect(find.text('Ingredients'), findsNothing);
      expect(find.text('Safety information'), findsNothing);
    });

    testWidgets('a FAQ row opens its answer', (tester) async {
      ProductRepository.detailOverride = (_) async => adminContent;

      await pumpDetail(tester, doloWithId);

      final question = adminContent.faqs.first.question;
      await tester.tap(find.text(question));
      await tester.pumpAndSettle();

      expect(find.textContaining('with or without food'), findsOneWidget);
    });
  });
}
