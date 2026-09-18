import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/patients/patient_book.dart';
import 'package:shield/module/prescription/prescription_form_sheet.dart';
import 'package:shield/module/prescription/prescription_record.dart';
import 'package:shield/module/prescription/upload_prescription_screen.dart';

final _patient = Patient(
  id: 'p1',
  name: 'Test Patient',
  phone: '9000000000',
  dob: DateTime(1990, 1, 1),
  gender: PatientGender.male,
  relation: PatientRelation.self,
);

void main() {
  final book = PrescriptionBook.instance;

  setUp(book.reset);
  tearDown(book.reset);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: UploadPrescriptionScreen()),
    );
    await tester.pumpAndSettle();
  }

  group('the intake card', () {
    testWidgets('shows once medicines arrive, even before the order is placed', (
      tester,
    ) async {
      final record = book.add(patient: _patient, fileName: 'script.jpg');
      book.applyIntakeCard(
        record.id,
        medicines: [
          const PrescriptionMedicine(
            name: 'Paracetamol',
            intake: IntakePattern(morning: 1, night: 1),
          ),
        ],
      );
      expect(record.isAwaitingOrder, isTrue);

      await pump(tester);

      // The intake header shows regardless; the medicine rows are inside its
      // own collapse/expand toggle, off by default — tap it open.
      expect(find.textContaining('The pharmacist then reads the script'), findsNothing);
      await tester.tap(find.text('Intake card ready'));
      await tester.pumpAndSettle();
      expect(find.text('Paracetamol'), findsOneWidget);
    });

    testWidgets('before any medicines arrive, shows the pre-order note instead', (
      tester,
    ) async {
      book.add(patient: _patient, fileName: 'script.jpg');

      await pump(tester);

      expect(find.textContaining('The pharmacist then reads the script'), findsOneWidget);
    });
  });

  group('deleting a prescription', () {
    testWidgets('asks for confirmation before removing it', (tester) async {
      book.add(patient: _patient, fileName: 'script.jpg');
      await pump(tester);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this prescription?'), findsOneWidget);
      expect(book.length, 1); // not removed yet
    });

    testWidgets('cancelling the confirmation keeps the record', (tester) async {
      book.add(patient: _patient, fileName: 'script.jpg');
      await pump(tester);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this prescription?'), findsNothing);
      expect(book.length, 1);
    });

    testWidgets('confirming removes the record from the book', (tester) async {
      book.add(patient: _patient, fileName: 'script.jpg');
      await pump(tester);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      // Two "Delete" texts on screen now: the card's own button (behind the
      // dialog) and the dialog's confirm action — the dialog's is the last
      // one painted.
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(book.length, 0);
      expect(find.text('Prescription removed'), findsOneWidget);
    });

    testWidgets(
      'a record already on the backend stays put if the delete call fails',
      (tester) async {
        final record = book.add(patient: _patient, fileName: 'script.jpg');
        // Simulates a card synced down from the backend — BackendHttp is
        // unconfigured under test, so softDelete reports failure for any
        // non-null remoteId, exactly like a real network failure would.
        book.attachRemoteId(record.id, '123');
        await pump(tester);

        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();

        // Still there — the local copy is never dropped ahead of a
        // confirmed backend delete, so a failure can never look like a
        // silent success that later reappears on refresh.
        expect(book.length, 1);
        expect(
          find.textContaining('Could not delete this'),
          findsOneWidget,
        );
      },
    );
  });

  group('adding another prescription', () {
    testWidgets(
      'is offered even while a prescription is still unordered',
      (tester) async {
        book.add(patient: _patient, fileName: 'script.jpg');
        await pump(tester);

        // Still unordered, so the bottom bar itself is "Proceed to
        // delivery" — the inline button is the one this test is after.
        expect(find.text('Proceed to delivery'), findsOneWidget);
        await tester.tap(find.text('Add prescription'));
        await tester.pumpAndSettle();

        expect(find.byType(PrescriptionFormSheet), findsOneWidget);
      },
    );
  });
}
