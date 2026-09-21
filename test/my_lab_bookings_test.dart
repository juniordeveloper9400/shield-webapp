import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/account/account_screen.dart';
import 'package:shield/module/auth/auth_service.dart';
import 'package:shield/module/labtest/lab_booking_record.dart';
import 'package:shield/module/labtest/lab_report_screen.dart';
import 'package:shield/module/labtest/my_lab_bookings_screen.dart';

// A 1x1 transparent PNG — a real, decodable image.
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

LabBookingRecord _booking({
  int id = 7,
  LabStage stage = LabStage.requested,
  String note = '',
  int reportPages = 0,
  DateTime? scheduledFor,
}) => LabBookingRecord(
  id: id,
  packageName: 'Full Body Checkup',
  patients: 2,
  total: 1998,
  stage: stage,
  note: note,
  reportPages: reportPages,
  scheduledFor: scheduledFor,
);

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  LabBookingSource source({
    List<LabBookingRecord>? bookings,
    List<String>? pages,
    List<int>? askedReportFor,
  }) => LabBookingSource(
    loadBookings: () async => bookings,
    loadReportPages: (id) async {
      askedReportFor?.add(id);
      return pages;
    },
  );

  group('LabBookingRecord', () {
    test('reads the backend JSON, with the same code the console shows', () {
      final record = LabBookingRecord.fromJson({
        'id': 7,
        'packageName': 'Full Body Checkup',
        'patientsCount': 2,
        'totalPrice': '1998.00',
        'status': 'REPORT_READY',
        'scheduledFor': '2026-09-25T04:30:00.000Z',
        'note': ' Come fasting ',
        'reportPages': 3,
        'createdAt': '2026-09-20T10:00:00.000Z',
      });

      expect(record.code, 'LB-0007');
      expect(record.total, 1998);
      expect(record.stage, LabStage.reportReady);
      expect(record.note, 'Come fasting');
      expect(record.reportPages, 3);
      expect(record.scheduledFor, isNotNull);
      expect(record.reportAvailable, isTrue);
    });

    test('a report is available only when ready and pages are attached', () {
      expect(_booking(stage: LabStage.reportReady).reportAvailable, isFalse);
      expect(
        _booking(stage: LabStage.sampleCollected, reportPages: 2).reportAvailable,
        isFalse,
      );
      expect(
        _booking(stage: LabStage.reportReady, reportPages: 1).reportAvailable,
        isTrue,
      );
    });

    test('every status value maps, and an unknown one reads as requested', () {
      expect(LabStage.parse('REQUESTED'), LabStage.requested);
      expect(LabStage.parse('CONFIRMED'), LabStage.confirmed);
      expect(LabStage.parse('SAMPLE_COLLECTED'), LabStage.sampleCollected);
      expect(LabStage.parse('REPORT_READY'), LabStage.reportReady);
      expect(LabStage.parse('CANCELLED'), LabStage.cancelled);
      expect(LabStage.parse('something new'), LabStage.requested);
      expect(LabStage.parse(null), LabStage.requested);
    });

    test('missing fields fall back instead of throwing', () {
      final record = LabBookingRecord.fromJson({'id': 1});
      expect(record.packageName, 'Lab test');
      expect(record.patients, 1);
      expect(record.total, 0);
      expect(record.note, '');
      expect(record.scheduledFor, isNull);
    });
  });

  group('My Lab Bookings', () {
    testWidgets('says so when there are no bookings', (tester) async {
      await pump(tester, MyLabBookingsScreen(source: source(bookings: [])));

      expect(find.text('No lab bookings yet'), findsOneWidget);
    });

    testWidgets('a failed load says so and can be retried', (tester) async {
      var calls = 0;
      final retrying = LabBookingSource(
        loadBookings: () async => ++calls == 1 ? null : [_booking()],
        loadReportPages: (_) async => const [],
      );
      await pump(tester, MyLabBookingsScreen(source: retrying));

      expect(find.text('Could not load your bookings'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Full Body Checkup'), findsOneWidget);
    });

    testWidgets('shows the booking, its status, schedule and the lab note', (
      tester,
    ) async {
      await pump(
        tester,
        MyLabBookingsScreen(
          source: source(
            bookings: [
              _booking(
                stage: LabStage.confirmed,
                note: 'Please come fasting for 10 hours.',
                scheduledFor: DateTime(2026, 9, 25, 9, 30),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Full Body Checkup'), findsOneWidget);
      expect(find.textContaining('LB-0007 · 2 patients · ₹1,998'), findsOneWidget);
      // The chip and the progress bar both name the stage.
      expect(find.text('Confirmed'), findsNWidgets(2));
      expect(find.text('Scheduled 25 Sep 2026, 09:30 AM'), findsOneWidget);
      expect(find.text('Please come fasting for 10 hours.'), findsOneWidget);
      expect(find.textContaining('View report'), findsNothing);
    });

    testWidgets('a cancelled booking shows no progress or schedule', (
      tester,
    ) async {
      await pump(
        tester,
        MyLabBookingsScreen(
          source: source(
            bookings: [
              _booking(
                stage: LabStage.cancelled,
                scheduledFor: DateTime(2026, 9, 25, 9, 30),
              ),
            ],
          ),
        ),
      );

      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Sample collected'), findsNothing);
      expect(find.textContaining('Scheduled'), findsNothing);
    });

    testWidgets('a ready report opens from the booking, page by page', (
      tester,
    ) async {
      final asked = <int>[];
      await pump(
        tester,
        MyLabBookingsScreen(
          source: source(
            bookings: [_booking(stage: LabStage.reportReady, reportPages: 2)],
            pages: [_png, _png],
            askedReportFor: asked,
          ),
        ),
      );

      expect(find.text('View report (2 pages)'), findsOneWidget);
      // Pages are not fetched until the member opens the report.
      expect(asked, isEmpty);

      await tester.tap(find.text('View report (2 pages)'));
      await tester.pumpAndSettle();

      expect(find.byType(LabReportScreen), findsOneWidget);
      expect(asked, [7]);
      expect(find.text('Lab report · LB-0007'), findsOneWidget);
      expect(find.text('Page 1 of 2 — swipe for more'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2 — swipe for more'), findsOneWidget);
    });

    testWidgets('a single-page report says so', (tester) async {
      await pump(
        tester,
        MyLabBookingsScreen(
          source: source(
            bookings: [_booking(stage: LabStage.reportReady, reportPages: 1)],
            pages: [_png],
          ),
        ),
      );

      await tester.tap(find.text('View report'));
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 1'), findsOneWidget);
    });
  });

  group('the report screen', () {
    testWidgets('an empty report says it is not available yet', (tester) async {
      await pump(
        tester,
        LabReportScreen(
          booking: _booking(stage: LabStage.reportReady, reportPages: 1),
          source: source(pages: const []),
        ),
      );

      expect(find.text('Report not available yet'), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      var calls = 0;
      final retrying = LabBookingSource(
        loadBookings: () async => const [],
        loadReportPages: (_) async => ++calls == 1 ? null : [_png],
      );
      await pump(
        tester,
        LabReportScreen(
          booking: _booking(stage: LabStage.reportReady, reportPages: 1),
          source: retrying,
        ),
      );

      expect(find.text('Could not load the report'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 1'), findsOneWidget);
    });
  });

  group('the Account menu', () {
    setUp(() => AuthService.instance.reset());
    tearDown(() => AuthService.instance.reset());

    testWidgets('offers My Lab Bookings and opens it', (tester) async {
      AuthService.instance.signInAs();
      await pump(tester, const AccountScreen());

      await tester.tap(find.text('My Lab Bookings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(MyLabBookingsScreen), findsOneWidget);
    });
  });
}
