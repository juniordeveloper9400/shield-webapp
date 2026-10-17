import 'package:shield/data/backend/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/labtest/lab_cart_service.dart';
import 'package:shield/module/labtest/lab_package.dart';
import 'package:shield/module/labtest/lab_patient_picker_sheet.dart';
import 'package:shield/module/location/address_book.dart';
import 'package:shield/module/patients/patient_book.dart';

const _activeLife = LabPackage(
  id: '2',
  name: 'Active Life',
  testCount: 85,
  profileCount: 8,
  price: '1,299',
  mrp: '3,248',
);

void main() {
  setUp(() {
    LabCartService.instance.reset();
    PatientBook.instance.reset();
    AddressBook.instance.reset();
  });
  tearDown(() {
    LabCartService.instance.reset();
    PatientBook.instance.reset();
    AddressBook.instance.reset();
  });
  List<Patient> somePatients(int count) => [
    for (var i = 1; i <= count; i++)
      PatientBook.instance.add(
        name: 'Patient $i',
        phone: '900000000$i',
        dob: DateTime(1990, 1, i),
        gender: PatientGender.other,
        relation: PatientRelation.other,
      ),
  ];
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(400, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  test('a patient is charged once per test', () {
    final patients = somePatients(2);
    LabCartService.instance.book(
      _activeLife,
      patients: [patients[0], patients[0], patients[1]],
    );
    expect(LabCartService.instance.bookings.single.patients.length, 2);
    expect(LabCartService.instance.payable, 2598);
  });
  test('skipped details send only a label, without invented demographics', () {
    final guest = Patient.labGuest(1);
    expect(LabBookingPatientInput(patient: guest).toJson(), {
      'name': 'Patient 1',
    });
    expect(guest.copyWith(name: 'Patient 1').detailsPending, isTrue);
  });

  group('the patient sheet', () {
    testWidgets(
      'Skip keeps the patient count without saving fake patient details',
      (tester) async {
        await pump(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('open skip flow'),
                onPressed: () async {
                  final chosen = await LabPatientPickerSheet.show(
                    context,
                    _activeLife,
                  );
                  if (chosen != null) {
                    LabCartService.instance.book(_activeLife, patients: chosen);
                  }
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('open skip flow'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2 patients'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip patient details'));
        await tester.pumpAndSettle();
        expect(find.text('Confirm patients'), findsOneWidget);
        expect(find.text('Patient 1'), findsOneWidget);
        expect(find.text('Patient 2'), findsOneWidget);
        expect(find.text('Details not provided'), findsNWidgets(2));
        await tester.tap(find.text('Add \u00b7 \u20b92,598'));
        await tester.pumpAndSettle();
        expect(LabCartService.instance.patientCount, 2);
        expect(LabCartService.instance.payable, 2598);
        expect(PatientBook.instance.isEmpty, isTrue);
      },
    );

    testWidgets('Back cancels adding another patient and keeps the review', (
      tester,
    ) async {
      final patients = somePatients(1);
      await pump(
        tester,
        Scaffold(
          body: LabPatientPickerSheet(package: _activeLife, initial: patients),
        ),
      );
      await tester.tap(find.text('Add another patient'));
      await tester.pumpAndSettle();
      expect(find.text('Patient 2 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm patients'), findsOneWidget);
      expect(
        find.text('1 patient \u00d7 \u20b91,299 = \u20b91,299'),
        findsOneWidget,
      );
      expect(find.text(patients.single.name), findsOneWidget);
    });

    testWidgets('a new patient can be added alongside a saved patient', (
      tester,
    ) async {
      final saved = somePatients(1).single;
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Add'),
              onPressed: () async {
                final chosen = await LabPatientPickerSheet.show(
                  context,
                  _activeLife,
                );
                if (chosen != null) {
                  LabCartService.instance.book(_activeLife, patients: chosen);
                }
              },
            ),
          ),
        ),
        size: const Size(400, 1800),
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 patients'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(saved.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a new patient'));
      await tester.pumpAndSettle();
      Future<void> fill(String label, String value) async {
        final field = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
      }

      await fill('Full name', 'New Family Patient');
      await fill('Mobile number', '9000012345');
      await tester.tap(find.widgetWithText(TextFormField, 'Date of birth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await fill('Pincode', '682001');
      await fill('House no / Floor / Building', '12 Lake View Road');
      await fill('Area / Locality', 'Kochi');
      await fill('First name', 'Receiver');
      await fill('Mobile Number', '9000012345');
      await tester.ensureVisible(find.text('Save patient'));
      await tester.tap(find.text('Save patient'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm patients'), findsOneWidget);
      expect(find.text(saved.name), findsOneWidget);
      expect(find.text('New Family Patient'), findsOneWidget);
      await tester.tap(find.text('Add · ₹2,598'));
      await tester.pumpAndSettle();
      expect(
        LabCartService.instance.bookings.single.patients.map((p) => p.name),
        [saved.name, 'New Family Patient'],
      );
      expect(PatientBook.instance.patients.length, 2);
    });

    testWidgets(
      'new patient details can be saved with the address left blank',
      (tester) async {
        final saved = somePatients(1).single;
        await pump(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Add'),
                onPressed: () async {
                  final chosen = await LabPatientPickerSheet.show(
                    context,
                    _activeLife,
                  );
                  if (chosen != null) {
                    LabCartService.instance.book(_activeLife, patients: chosen);
                  }
                },
              ),
            ),
          ),
          size: const Size(400, 1800),
        );
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2 patients'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(saved.name));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add a new patient'));
        await tester.pumpAndSettle();
        Future<void> fill(String label, String value) async {
          final field = find.widgetWithText(TextFormField, label);
          await tester.ensureVisible(field);
          await tester.enterText(field, value);
        }

        await fill('Full name', 'New Family Patient');
        await fill('Mobile number', '9000012345');
        await tester.tap(find.widgetWithText(TextFormField, 'Date of birth'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save patient'));
        await tester.tap(find.text('Save patient'));
        await tester.pumpAndSettle();
        expect(find.text('Confirm patients'), findsOneWidget);
        expect(find.text(saved.name), findsOneWidget);
        expect(find.text('New Family Patient'), findsOneWidget);
        await tester.tap(find.text('Add · ₹2,598'));
        await tester.pumpAndSettle();
        expect(
          LabCartService.instance.bookings.single.patients.map((p) => p.name),
          [saved.name, 'New Family Patient'],
        );
        expect(PatientBook.instance.patients.length, 2);
        final added = PatientBook.instance.patients.last;
        expect(AddressBook.instance.forPatient(added.id), isNull);
      },
    );

    testWidgets('count picker scrolls on a short landscape screen', (
      tester,
    ) async {
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => LabPatientPickerSheet.show(context, _activeLife),
              child: const Text('open'),
            ),
          ),
        ),
        size: const Size(740, 360),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('5 patients'));
      await tester.tap(find.text('5 patients'));
      await tester.pumpAndSettle();
      expect(find.text('Patient 1 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'shows the full selected-count price while collecting patients',
      (tester) async {
        somePatients(2);
        await pump(
          tester,
          const Scaffold(body: LabPatientPickerSheet(package: _activeLife)),
        );
        await tester.tap(find.text('2 patients'));
        await tester.pumpAndSettle();
        expect(find.text('2 patients × ₹1,299 = ₹2,598'), findsOneWidget);
        await tester.tap(find.text('Patient 1'));
        await tester.pumpAndSettle();
        expect(find.text('Patient 1'), findsNothing);
        expect(find.text('Patient 2 of 2'), findsOneWidget);
        expect(find.text('2 patients × ₹1,299 = ₹2,598'), findsOneWidget);
      },
    );

    testWidgets('opens on the old-style headcount picker', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => LabPatientPickerSheet.show(context, _activeLife),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Select number of patients'), findsOneWidget);
      expect(find.text('1 patient'), findsOneWidget);
      expect(find.text('5 patients'), findsOneWidget);
    });

    testWidgets(
      'picking a count collects that many patients one at a time, each a saved-patient shortcut away, then prices the selection',
      (tester) async {
        final patients = somePatients(2);
        await pump(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    LabPatientPickerSheet.show(context, _activeLife),
                child: const Text('open'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('2 patients'));
        await tester.pumpAndSettle();
        expect(find.text('Patient 1 of 2'), findsOneWidget);
        expect(find.text(patients[0].name), findsOneWidget);

        await tester.tap(find.text(patients[0].name));
        await tester.pumpAndSettle();
        expect(find.text('Patient 2 of 2'), findsOneWidget);

        await tester.tap(find.text(patients[1].name));
        await tester.pumpAndSettle();

        // Both slots filled — the review step, with the stable count-based price.
        expect(find.text('Add · ₹2,598'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Add · ₹2,598'),
              )
              .onPressed,
          isNotNull,
        );
      },
    );
  });
}
