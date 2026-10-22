import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/account/account_screen.dart';
import 'package:shield/module/auth/auth_service.dart';
import 'package:shield/module/labtest/lab_booking_detail_screen.dart';
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
  String packageName = 'Full Body Checkup',
  int patients = 2,
  double total = 1998,
  String? orderGroupId,
}) => LabBookingRecord(
  id: id,
  packageName: packageName,
  patients: patients,
  total: total,
  stage: stage,
  note: note,
  reportPages: reportPages,
  scheduledFor: scheduledFor,
  orderGroupId: orderGroupId,
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
        'stage': 'COMPLETED',
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
      expect(record.stage, LabStage.completed);
      expect(record.note, 'Come fasting');
      expect(record.reportPages, 3);
      expect(record.scheduledFor, isNotNull);
      expect(record.reportAvailable, isTrue);
    });

    test('a report is available only when ready and pages are attached', () {
      expect(_booking(stage: LabStage.completed).reportAvailable, isFalse);
      expect(
        _booking(stage: LabStage.billed, reportPages: 2).reportAvailable,
        isFalse,
      );
      expect(
        _booking(stage: LabStage.completed, reportPages: 1).reportAvailable,
        isTrue,
      );
    });

    test('every status value maps, and an unknown one reads as requested', () {
      expect(LabStage.parse('REQUESTED'), LabStage.requested);
      expect(LabStage.parse('VERIFIED'), LabStage.verified);
      expect(LabStage.parse('BILLED'), LabStage.billed);
      expect(LabStage.parse('COMPLETED'), LabStage.completed);
      // An older backend that sends only the raw booking status.
      expect(LabStage.parse('CONFIRMED'), LabStage.verified);
      expect(LabStage.parse('REPORT_READY'), LabStage.completed);
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

      expect(find.text('No lab orders yet'), findsOneWidget);
    });

    testWidgets('a failed load says so and can be retried', (tester) async {
      var calls = 0;
      final retrying = LabBookingSource(
        loadBookings: () async => ++calls == 1 ? null : [_booking()],
        loadReportPages: (_) async => const [],
      );
      await pump(tester, MyLabBookingsScreen(source: retrying));

      expect(find.text('Could not load your orders'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Full Body Checkup'), findsOneWidget);
    });

    testWidgets(
      'shows the booking summary on the list, with full detail behind Track booking',
      (tester) async {
        await pump(
          tester,
          MyLabBookingsScreen(
            source: source(
              bookings: [
                _booking(
                  stage: LabStage.verified,
                  note: 'Please come fasting for 10 hours.',
                  scheduledFor: DateTime(2026, 9, 25, 9, 30),
                ),
              ],
            ),
          ),
        );

        expect(find.text('Full Body Checkup'), findsOneWidget);
        expect(
          find.textContaining('LB-0007 · 2 patients · ₹1,998'),
          findsOneWidget,
        );
        expect(find.text('Verified'), findsOneWidget);
        expect(find.textContaining('View report'), findsNothing);
        expect(find.textContaining('Scheduled'), findsNothing);
        expect(find.text('Please come fasting for 10 hours.'), findsNothing);

        await tester.tap(find.text('View order'));
        await tester.pumpAndSettle();

        expect(find.byType(LabBookingDetailScreen), findsOneWidget);
        // The chip and the progress bar both name the stage.
        expect(find.text('Verified'), findsNWidgets(2));
        expect(find.text('Scheduled'), findsOneWidget);
        expect(find.text('25 Sep 2026, 09:30 AM'), findsOneWidget);
        expect(find.text('Please come fasting for 10 hours.'), findsOneWidget);
      },
    );

    testWidgets(
      'two or more tests placed in one checkout show as a single order',
      (tester) async {
        await pump(
          tester,
          MyLabBookingsScreen(
            source: source(
              bookings: [
                _booking(
                  id: 9,
                  packageName: 'Thyroid Profile',
                  patients: 1,
                  total: 450,
                  stage: LabStage.verified,
                  orderGroupId: 'order-abc',
                ),
                _booking(
                  id: 8,
                  packageName: 'Full Body Checkup',
                  patients: 2,
                  total: 1998,
                  stage: LabStage.requested,
                  orderGroupId: 'order-abc',
                ),
              ],
            ),
          ),
        );

        // One card for the order — its code names the earliest test in it,
        // not the one that happens to list first.
        expect(find.text('Order LB-0008'), findsOneWidget);
        expect(find.text('2 tests'), findsOneWidget);
        // Every test it covers is named, each with its own status.
        expect(find.text('Full Body Checkup'), findsOneWidget);
        expect(find.text('Thyroid Profile'), findsOneWidget);
        expect(find.text('Requested'), findsOneWidget);
        expect(find.text('Verified'), findsOneWidget);

        await tester.tap(find.text('Thyroid Profile'));
        await tester.pumpAndSettle();

        // Tapping one test opens exactly that test's own detail screen.
        expect(find.byType(LabBookingDetailScreen), findsOneWidget);
        expect(find.text('Thyroid Profile'), findsWidgets);
        expect(find.text('Full Body Checkup'), findsNothing);
      },
    );

    testWidgets(
      'a lone test still shows its own card, no order grouping needed',
      (tester) async {
        await pump(
          tester,
          MyLabBookingsScreen(
            source: source(bookings: [_booking(id: 5, orderGroupId: null)]),
          ),
        );

        expect(find.text('Order LB-0005'), findsNothing);
      },
    );

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

      await tester.tap(find.text('View order'));
      await tester.pumpAndSettle();

      expect(find.text('Billed'), findsNothing);
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
            bookings: [_booking(stage: LabStage.completed, reportPages: 2)],
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
            bookings: [_booking(stage: LabStage.completed, reportPages: 1)],
            pages: [_png],
          ),
        ),
      );

      await tester.tap(find.text('View report'));
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 1'), findsOneWidget);
    });

    testWidgets(
      'follows a status the lab set live, with nobody pulling to refresh',
      (tester) async {
        var stage = LabStage.requested;
        final live = LabBookingSource(
          loadBookings: () async => [_booking(stage: stage)],
          loadReportPages: (_) async => null,
        );

        await pump(tester, MyLabBookingsScreen(source: live));
        expect(find.text('Requested'), findsOneWidget);

        // The lab confirms it from the console — nothing happens here. The
        // 15s timer only fires while the app is in the foreground; a widget
        // test starts with no lifecycle state at all, so this says so
        // explicitly, the same as the real app does on launch/resume.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        stage = LabStage.verified;
        await tester.pump(const Duration(seconds: 16));
        await tester.pumpAndSettle();
        expect(find.text('Verified'), findsOneWidget);
        expect(find.text('Requested'), findsNothing);

        // Leaving the screen stops the polling — advancing well past
        // another interval afterwards must not throw.
        await tester.pumpWidget(const SizedBox.shrink());
        stage = LabStage.completed;
        await tester.pump(const Duration(seconds: 31));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('the report screen', () {
    testWidgets('an empty report says it is not available yet', (tester) async {
      await pump(
        tester,
        LabReportScreen(
          booking: _booking(stage: LabStage.completed, reportPages: 1),
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
          booking: _booking(stage: LabStage.completed, reportPages: 1),
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

    // Lab bookings & reports live only in the Lab tab now ("My Lab
    // Bookings & Reports" — see lab_bookings_banner_test.dart) — no longer
    // duplicated here under Account. Matches the same change in the root
    // app.
    testWidgets('does not offer My Lab Bookings — that lives in the Lab tab now', (
      tester,
    ) async {
      AuthService.instance.signInAs();
      await pump(tester, const AccountScreen());

      expect(find.text('My Lab Bookings'), findsNothing);
    });
  });
}
