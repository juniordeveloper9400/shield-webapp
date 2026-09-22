import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/care_repository.dart';
import 'package:shield/module/labtest/lab_cart_screen.dart';
import 'package:shield/module/labtest/lab_cart_service.dart';
import 'package:shield/module/labtest/lab_package.dart';
import 'package:shield/module/labtest/lab_store.dart';
import 'package:shield/module/labtest/lab_store_picker_sheet.dart';
import 'package:shield/module/registration/registration_service.dart';

const _activeLife = LabPackage(
  id: '2',
  name: 'Active Life',
  testCount: 85,
  profileCount: 8,
  price: '1,299',
  mrp: '3,248',
);

const _melattur = LabStore(
  id: 1,
  code: 'SHD-MEL',
  name: 'Sahakar 360 Pharmacy Melattur',
  area: 'Melattur',
  city: 'Malappuram',
  pincode: '679326',
);

const _tirur = LabStore(
  id: 3,
  code: 'SHD-TIR',
  name: 'Sahakar 360 Pharmacy Tirur',
  area: 'Tirur',
  city: 'Malappuram',
  pincode: '676101',
);

/// The lab checkout's "Branch" row (`shield agent_invester`'s own mirror of
/// root's, reading live from `GET /v1/public/care/lab-stores` rather than
/// this app's static `StoreDirectory` — see `lab_store.dart`).
void main() {
  setUp(() {
    LabCartService.instance.reset();
    RegistrationService.instance.reset();
    CareRepository.labStoresOverride = () async => [_melattur, _tirur];
  });
  tearDown(() {
    LabCartService.instance.reset();
    RegistrationService.instance.reset();
    CareRepository.labStoresOverride = null;
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('asks for a branch when nothing is registered or chosen', (
    tester,
  ) async {
    CareRepository.labStoresOverride = () async => [];
    LabCartService.instance.book(_activeLife, patients: 2);
    await pump(tester, const LabCartScreen());

    expect(find.text('Choose a branch'), findsOneWidget);
  });

  testWidgets(
    'defaults to the member\'s home branch once the live list loads',
    (tester) async {
      RegistrationService.instance.debugSet(
        RegistrationStatus.registered,
        profile: Registration(
          name: 'Asha',
          phone: '9999999999',
          email: 'asha@example.com',
          gender: Gender.female,
          dob: DateTime(1994, 9, 4),
          address: 'House',
          place: 'Tirur',
          pincode: '676101',
          state: 'Kerala',
          storeId: 'SHD-TIR',
        ),
      );
      LabCartService.instance.book(_activeLife, patients: 2);
      await pump(tester, const LabCartScreen());

      expect(find.text('Sahakar 360 Pharmacy Tirur'), findsOneWidget);
      expect(LabCartService.instance.store?.id, 3);
    },
  );

  testWidgets('opening the picker and choosing a branch reaches the basket', (
    tester,
  ) async {
    LabCartService.instance.book(_activeLife, patients: 2);
    await pump(tester, const LabCartScreen());

    await tester.tap(find.text('Choose a branch'));
    await tester.pumpAndSettle();

    expect(find.byType(LabStorePickerSheet), findsOneWidget);
    expect(find.text('Sahakar 360 Pharmacy Melattur'), findsOneWidget);

    await tester.tap(find.text('Sahakar 360 Pharmacy Melattur'));
    await tester.pumpAndSettle();

    expect(LabCartService.instance.store?.id, 1);
    expect(find.text('Sahakar 360 Pharmacy Melattur'), findsOneWidget);
  });

  testWidgets(
    'the bill card itself updates on a same-length patient-count edit',
    (tester) async {
      // Regression check for a canonicalized `const _BillCard()` silently
      // going stale on this exact kind of edit — see root's identical test.
      LabCartService.instance.book(_activeLife, patients: 2);
      await pump(tester, const LabCartScreen());

      await tester.tap(find.text('2 patients'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 patients'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add · ₹5,196'));
      await tester.pumpAndSettle();

      expect(LabCartService.instance.bookings.single.patients, 4);
      expect(find.text('- ₹7,796'), findsOneWidget);
      expect(find.text('For 4 patients'), findsOneWidget);
    },
  );
}
