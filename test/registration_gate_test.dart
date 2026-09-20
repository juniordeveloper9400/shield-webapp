import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/registration_repository.dart';
import 'package:shield/module/cart/cart_control.dart';
import 'package:shield/module/cart/cart_service.dart';
import 'package:shield/module/registration/register_bar.dart';
import 'package:shield/module/registration/registration_gate.dart';
import 'package:shield/module/registration/registration_service.dart';

void main() {
  final asha = Registration(
    name: 'Asha',
    phone: '9876543210',
    email: 'asha@example.com',
    gender: Gender.female,
    dob: DateTime(1994, 9, 4),
    address: '1 Main St',
    place: 'Melattur',
    pincode: '679326',
    state: 'Kerala',
    storeId: 'SHD-MEL',
  );

  late RegistrationService service;

  setUp(() {
    service = RegistrationService.instance..reset();
    CartService.instance.clear();
  });
  tearDown(() {
    service.reset();
    CartService.instance.clear();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  group('RegisterBar', () {
    Future<void> pumpBar(WidgetTester tester) => pump(tester, const RegisterBar());

    testWidgets('is shown when the backend has said the member has not registered', (tester) async {
      service.debugSet(RegistrationStatus.notRegistered);
      await pumpBar(tester);

      expect(find.textContaining('Register now'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('is gone for a registered member', (tester) async {
      service.debugSet(RegistrationStatus.registered, profile: asha);
      await pumpBar(tester);

      expect(find.textContaining('Register'), findsNothing);
    });

    testWidgets('does not nag while the registration is still being looked up', (tester) async {
      // The refresh case: not known yet must never look like "not registered".
      for (final status in [RegistrationStatus.unknown, RegistrationStatus.checking]) {
        service.debugSet(status);
        await pumpBar(tester);
        expect(find.textContaining('Register'), findsNothing, reason: '$status');
      }
    });

    testWidgets('says it could not check — instead of asking to register — and offers a retry', (tester) async {
      var retried = false;
      service.debugSet(RegistrationStatus.unreachable);
      service.debugUse(
        lookup: (_) async {
          retried = true;
          return RegistrationLookup.registered(asha);
        },
        sessionReady: () => true,
        retryDelays: const [],
        sessionWait: Duration.zero,
        available: () => true,
      );
      // retry() needs to know who to ask about.
      service.loadForSignedInMember('9876543210').ignore();
      await pumpBar(tester);
      await tester.pumpAndSettle();
      retried = false;
      service.debugSet(RegistrationStatus.unreachable);
      await tester.pump();

      expect(find.text('Couldn’t check your registration'), findsOneWidget);
      expect(find.textContaining('Register now'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(retried, isTrue);
      expect(service.isRegistered, isTrue);
      expect(find.text('Couldn’t check your registration'), findsNothing);
    });
  });

  group('RegistrationGate.ensure', () {
    Future<bool?> runGate(WidgetTester tester, {String action = 'add items to your cart'}) async {
      bool? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await RegistrationGate.ensure(context, action: action),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      // Let the dialog and any short wait settle — without pumpAndSettle, which
      // a spinner would keep from ever settling.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return result;
    }

    testWidgets('lets a registered member straight through — no dialog at all', (tester) async {
      service.debugSet(RegistrationStatus.registered, profile: asha);

      final result = await runGate(tester);

      expect(result, isTrue);
      expect(find.text('Register to continue'), findsNothing);
    });

    testWidgets('tells an unregistered member why, in words that fit the action, and offers to register', (tester) async {
      service.debugSet(RegistrationStatus.notRegistered);

      final result = await runGate(tester, action: 'place orders');

      expect(result, isNull); // still waiting on the member's answer
      expect(find.text('Register to continue'), findsOneWidget);
      expect(find.textContaining('Only registered members can place orders'), findsOneWidget);
      expect(find.textContaining('500 reward points'), findsOneWidget);
    });

    testWidgets('"Not now" stops the action', (tester) async {
      service.debugSet(RegistrationStatus.notRegistered);
      bool? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await RegistrationGate.ensure(context),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.text('Register to continue'), findsNothing);
    });

    testWidgets('waits for a lookup that is still running, and lets a registered member through', (tester) async {
      // A refresh: the answer is not in yet. The gate must not turn them away.
      service.debugUse(
        available: () => true,
        sessionReady: () => true,
        retryDelays: const [],
        sessionWait: Duration.zero,
        lookup: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          return RegistrationLookup.registered(asha);
        },
      );
      service.loadForSignedInMember('9876543210').ignore();
      await tester.pump();
      expect(service.status, RegistrationStatus.checking);

      bool? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await RegistrationGate.ensure(context),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // the spinner shows past ~350ms
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(result, isTrue);
      expect(find.text('Register to continue'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('says it could not check — and does not send a possibly-registered member to register', (tester) async {
      service.debugUse(
        available: () => true,
        sessionReady: () => true,
        retryDelays: const [],
        sessionWait: Duration.zero,
        lookup: (_) async => const RegistrationLookup.unavailable(),
      );
      service.loadForSignedInMember('9876543210').ignore();
      await tester.pump();

      bool? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await RegistrationGate.ensure(context),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(result, isFalse);
      expect(find.text('Register to continue'), findsNothing);
      expect(find.textContaining('couldn’t check your registration'), findsOneWidget);
    });
  });

  group('the ADD button', () {
    Future<void> pumpAdd(WidgetTester tester) => pump(
      tester,
      const Center(
        child: SizedBox(
          width: 160,
          child: CartControl(name: 'Paracetamol 500mg', pack: 'Strip of 15', price: '20', mrp: '25'),
        ),
      ),
    );

    testWidgets('does not add to the cart for an unregistered member — it asks them to register', (tester) async {
      service.debugSet(RegistrationStatus.notRegistered);
      await pumpAdd(tester);

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();

      expect(find.text('Register to continue'), findsOneWidget);
      expect(find.textContaining('add items to your cart'), findsOneWidget);
      expect(CartService.instance.quantityFor('Paracetamol 500mg'), 0);
    });

    testWidgets('adds to the cart for a registered member', (tester) async {
      service.debugSet(RegistrationStatus.registered, profile: asha);
      await pumpAdd(tester);

      await tester.tap(find.text('ADD'));
      await tester.pumpAndSettle();

      expect(find.text('Register to continue'), findsNothing);
      expect(CartService.instance.quantityFor('Paracetamol 500mg'), 1);
    });
  });
}
