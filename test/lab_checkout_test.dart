import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/care_repository.dart';
import 'package:shield/module/auth/auth_service.dart';
import 'package:shield/module/auth/login_screen.dart';
import 'package:shield/module/labtest/lab_booking_placed_screen.dart';
import 'package:shield/module/labtest/lab_cart_screen.dart';
import 'package:shield/module/labtest/lab_cart_service.dart';
import 'package:shield/module/labtest/lab_checkout_screen.dart';
import 'package:shield/module/labtest/lab_package.dart';
import 'package:shield/module/labtest/lab_store.dart';
import 'package:shield/module/location/address_book.dart';
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

final _registeredProfile = Registration(
  name: 'Asha',
  phone: '9000000002',
  email: 'asha@example.com',
  gender: Gender.female,
  dob: DateTime(1994, 9, 4),
  address: 'House',
  place: 'Melattur',
  pincode: '679326',
  state: 'Kerala',
  storeId: 'SHD-MEL',
);

/// The lab cart's "Proceed to checkout" → [LabCheckoutScreen] → "Place lab
/// test" flow — this app's own mirror of root's identical test, adapted to
/// its backend-sourced branch list and [AuthFlow.guardRegistered] gate.
void main() {
  setUp(() {
    LabCartService.instance.reset();
    AuthService.instance.reset();
    RegistrationService.instance.reset();
    AddressBook.instance.reset();
    CareRepository.labStoresOverride = () async => [_melattur];
  });
  tearDown(() {
    LabCartService.instance.reset();
    AuthService.instance.reset();
    RegistrationService.instance.reset();
    AddressBook.instance.reset();
    CareRepository.labStoresOverride = null;
  });

  void giveAddress() {
    AddressBook.instance.add(
      const Address(
        pincode: '679326',
        house: '12/A',
        area: 'Palm Grove',
        firstName: 'Asha',
        phone: '9000000002',
        label: AddressLabel.home,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  void registerAndSignIn() {
    AuthService.instance.signInAs(phone: _registeredProfile.phone);
    RegistrationService.instance.debugSet(
      RegistrationStatus.registered,
      profile: _registeredProfile,
    );
  }

  group('proceeding to checkout', () {
    testWidgets(
      'signed in and registered, with a branch resolved, opens a real '
      'checkout screen — not a fake "choosing a slot" toast',
      (tester) async {
        registerAndSignIn();
        LabCartService.instance.book(_activeLife, patients: 2);
        await pump(tester, const LabCartScreen());

        expect(find.text('Proceed to checkout'), findsOneWidget);
        await tester.tap(find.text('Proceed to checkout'));
        await tester.pumpAndSettle();

        expect(find.byType(LabCheckoutScreen), findsOneWidget);
        expect(find.text('Booking summary'), findsOneWidget);
        expect(find.text('Active Life'), findsOneWidget);
        expect(find.text('Place lab test'), findsOneWidget);
      },
    );

    testWidgets('signed out, asks to sign in before opening checkout', (
      tester,
    ) async {
      LabCartService.instance.book(_activeLife, patients: 2);
      await pump(tester, const LabCartScreen());

      await tester.tap(find.text('Proceed to checkout'));
      await tester.pumpAndSettle();

      expect(find.byType(LabCheckoutScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
      'a delivery address is required to place the booking, and the row '
      'picks up an address added elsewhere',
      (tester) async {
        registerAndSignIn();
        LabCartService.instance.book(_activeLife, patients: 2);
        await pump(tester, const LabCartScreen());
        await tester.tap(find.text('Proceed to checkout'));
        await tester.pumpAndSettle();

        // Nothing on file yet: the row asks for one, same red-border guard
        // the branch row already uses, and "Place lab test" is disabled —
        // same as a missing branch already disables it.
        expect(find.text('Choose a delivery address'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Place lab test'),
              )
              .onPressed,
          isNull,
        );

        // Added straight on AddressBook — the same singleton
        // AddressSelectionScreen (opened from "Change") would have written
        // to — and the row picks it up without anything else changing.
        giveAddress();
        await tester.pumpAndSettle();
        expect(find.text('Home (679326)'), findsOneWidget);

        await tester.tap(find.text('Place lab test'));
        await tester.pumpAndSettle();
        expect(find.byType(LabBookingPlacedScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Place lab test files the booking, empties the basket and shows the '
      'confirmation screen',
      (tester) async {
        registerAndSignIn();
        giveAddress();
        LabCartService.instance.book(_activeLife, patients: 2);
        await pump(tester, const LabCartScreen());
        await tester.tap(find.text('Proceed to checkout'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Place lab test'));
        await tester.pumpAndSettle();

        expect(find.byType(LabBookingPlacedScreen), findsOneWidget);
        expect(find.text('Lab test booked'), findsOneWidget);
        expect(LabCartService.instance.isEmpty, isTrue);
      },
    );
  });
}
