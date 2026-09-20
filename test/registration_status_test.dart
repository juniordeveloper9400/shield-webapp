import 'package:flutter_test/flutter_test.dart';

import 'package:shield/data/backend/registration_repository.dart';
import 'package:shield/module/registration/registration_service.dart';

/// The bug this pins down: after a page refresh the app asked for the member's
/// registration before the backend session existed, took the failed answer for
/// "not registered", and never asked again — so a registered agent was shown
/// "Register now" again. Now "not registered" is only ever the backend's own
/// answer.
void main() {
  final asha = Registration(
    name: 'Asha',
    phone: '9876543210',
    email: 'asha@example.com',
    gender: Gender.female,
    dob: _dob,
    address: '1 Main St',
    place: 'Melattur',
    pincode: '679326',
    state: 'Kerala',
    storeId: 'SHD-MEL',
  );

  late RegistrationService service;
  late List<RegistrationStatus> seen;

  /// No real waiting: retries and the session wait collapse to nothing.
  void quick(RegistrationService s, {
    required Future<RegistrationLookup> Function(String) lookup,
    bool Function()? sessionReady,
    List<Duration> retryDelays = const [Duration.zero, Duration.zero, Duration.zero],
    Future<void> Function(Registration)? persist,
    bool available = true,
  }) {
    s.debugUse(
      lookup: lookup,
      persist: persist,
      available: () => available,
      sessionReady: sessionReady ?? () => true,
      retryDelays: retryDelays,
      sessionWait: Duration.zero,
    );
  }

  setUp(() {
    service = RegistrationService.instance..reset();
    seen = [];
    service.addListener(() => seen.add(service.status));
  });
  tearDown(() => service.reset());

  group('reading the registration', () {
    test('a registered member ends up registered, with their saved profile', () async {
      quick(service, lookup: (_) async => RegistrationLookup.registered(asha));

      await service.loadForSignedInMember('9876543210');

      expect(service.status, RegistrationStatus.registered);
      expect(service.isRegistered, isTrue);
      expect(service.profile?.storeId, 'SHD-MEL');
      expect(service.shouldPrompt, isFalse);
      expect(service.isConfirmedUnregistered, isFalse);
    });

    test('the refresh race: no answer yet, then the answer — never told to register in between', () async {
      // A page refresh: the first asks find no backend session, so they fail.
      var asks = 0;
      quick(
        service,
        lookup: (_) async {
          asks++;
          return asks < 3
              ? const RegistrationLookup.unavailable()
              : RegistrationLookup.registered(asha);
        },
      );

      await service.loadForSignedInMember('9876543210');

      expect(asks, 3);
      expect(service.isRegistered, isTrue);
      expect(seen, isNot(contains(RegistrationStatus.notRegistered)));
      expect(seen, isNot(contains(RegistrationStatus.unreachable)));
      expect(service.shouldPrompt, isFalse);
    });

    test('waits for the backend session before asking at all', () async {
      var sessionReady = false;
      var asked = false;
      quick(
        service,
        sessionReady: () => sessionReady,
        lookup: (_) async {
          asked = true;
          expect(sessionReady, isTrue, reason: 'must not ask before there is a session');
          return RegistrationLookup.registered(asha);
        },
      );
      service.debugUse(sessionWait: const Duration(seconds: 2));

      final loading = service.loadForSignedInMember('9876543210');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(asked, isFalse);
      expect(service.status, RegistrationStatus.checking);

      sessionReady = true; // the bridge finishes
      await loading;

      expect(asked, isTrue);
      expect(service.isRegistered, isTrue);
    });

    test('the backend saying "not registered" is the only thing that says so', () async {
      quick(service, lookup: (_) async => const RegistrationLookup.notRegistered());

      await service.loadForSignedInMember('9876543210');

      expect(service.status, RegistrationStatus.notRegistered);
      expect(service.isConfirmedUnregistered, isTrue);
      expect(service.shouldPrompt, isTrue);
      expect(service.isRegistered, isFalse);
    });

    test('when it can never be asked, the member is neither prompted nor turned away', () async {
      var asks = 0;
      quick(service, lookup: (_) async {
        asks++;
        return const RegistrationLookup.unavailable();
      });

      await service.loadForSignedInMember('9876543210');

      expect(asks, 4); // the first try + three retries
      expect(service.status, RegistrationStatus.unreachable);
      expect(service.isConfirmedUnregistered, isFalse);
      expect(service.shouldPrompt, isFalse);
      expect(seen, isNot(contains(RegistrationStatus.notRegistered)));
    });

    test('retry asks again after "couldn\'t check", and can recover', () async {
      var online = false;
      quick(service, lookup: (_) async {
        return online
            ? RegistrationLookup.registered(asha)
            : const RegistrationLookup.unavailable();
      });
      await service.loadForSignedInMember('9876543210');
      expect(service.status, RegistrationStatus.unreachable);

      online = true;
      await service.retry();

      expect(service.isRegistered, isTrue);
    });

    test('does nothing when already registered, and shares a lookup already running', () async {
      var asks = 0;
      quick(service, lookup: (_) async {
        asks++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return RegistrationLookup.registered(asha);
      });

      final a = service.loadForSignedInMember('9876543210');
      final b = service.loadForSignedInMember('9876543210');
      await Future.wait([a, b]);
      expect(asks, 1);

      await service.loadForSignedInMember('9876543210');
      expect(asks, 1); // already registered — not asked again
    });

    test('a build with no backend has nothing to look up: not registered', () async {
      quick(service, available: false, lookup: (_) async => throw StateError('must not be asked'));

      await service.loadForSignedInMember('9876543210');

      expect(service.status, RegistrationStatus.notRegistered);
    });

    test('an answer that arrives after sign-out is not applied to whoever is next', () async {
      quick(service, lookup: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return RegistrationLookup.registered(asha);
      });

      final loading = service.loadForSignedInMember('9876543210');
      service.clearForSignOut(); // signed out while the answer was in flight
      await loading;

      expect(service.isRegistered, isFalse);
      expect(service.status, RegistrationStatus.unknown);
    });

    test('sign-out forgets everything', () async {
      quick(service, lookup: (_) async => RegistrationLookup.registered(asha));
      await service.loadForSignedInMember('9876543210');

      service.clearForSignOut();

      expect(service.profile, isNull);
      expect(service.status, RegistrationStatus.unknown);
    });
  });

  group('ensureResolved (what the gate waits on)', () {
    test('returns straight away when registered', () async {
      service.debugSet(RegistrationStatus.registered, profile: asha);
      expect(await service.ensureResolved(), RegistrationStatus.registered);
    });

    test('waits for a lookup that is running', () async {
      quick(service, lookup: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return RegistrationLookup.registered(asha);
      });
      final loading = service.loadForSignedInMember('9876543210');

      expect(await service.ensureResolved(), RegistrationStatus.registered);
      await loading;
    });

    test('asks again when the last try could not be answered', () async {
      var online = false;
      quick(service, lookup: (_) async => online
          ? const RegistrationLookup.notRegistered()
          : const RegistrationLookup.unavailable());
      await service.loadForSignedInMember('9876543210');
      expect(service.status, RegistrationStatus.unreachable);

      online = true;
      expect(await service.ensureResolved(), RegistrationStatus.notRegistered);
    });
  });

  group('saving the registration', () {
    test('is written to the database first, and only then does the member count as registered', () async {
      var written = false;
      quick(service, lookup: (_) async => const RegistrationLookup.notRegistered(), persist: (r) async {
        written = true;
        expect(service.isRegistered, isFalse, reason: 'not registered until the write lands');
      });

      await service.submit(asha);

      expect(written, isTrue);
      expect(service.isRegistered, isTrue);
      expect(service.status, RegistrationStatus.registered);
      expect(service.shouldPrompt, isFalse);
    });

    test('a refused save leaves the member unregistered and says why', () async {
      quick(service, lookup: (_) async => const RegistrationLookup.notRegistered(), persist: (_) async {
        throw const RegistrationSaveException(
          "That branch isn't taking new registrations right now.",
          code: 'STORE_UNAVAILABLE',
        );
      });
      await service.loadForSignedInMember('9876543210');

      await expectLater(
        service.submit(asha),
        throwsA(isA<RegistrationSaveException>().having((e) => e.code, 'code', 'STORE_UNAVAILABLE')),
      );

      expect(service.isRegistered, isFalse);
      expect(service.status, RegistrationStatus.notRegistered);
    });

    test('waits for the backend session before saving', () async {
      var sessionReady = false;
      var saved = false;
      quick(
        service,
        sessionReady: () => sessionReady,
        lookup: (_) async => const RegistrationLookup.notRegistered(),
        persist: (_) async {
          saved = true;
          expect(sessionReady, isTrue);
        },
      );
      service.debugUse(sessionWait: const Duration(seconds: 2));

      final submitting = service.submit(asha);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(saved, isFalse);

      sessionReady = true;
      await submitting;
      expect(saved, isTrue);
    });

    test('without a backend it registers locally, as it always has', () async {
      quick(service, available: false, lookup: (_) async => throw StateError('unused'));

      await service.submit(asha);

      expect(service.isRegistered, isTrue);
    });

    test('a background edit updates the profile at once and never throws if the write fails', () async {
      quick(service, lookup: (_) async => RegistrationLookup.registered(asha), persist: (_) async {
        throw const RegistrationSaveException('offline');
      });
      await service.loadForSignedInMember('9876543210');

      service.save(asha.copyWith(storeId: 'SHD-TIR'));
      await Future<void>.delayed(Duration.zero);

      expect(service.profile?.storeId, 'SHD-TIR');
      expect(service.isRegistered, isTrue);
    });
  });
}

// A fixed date of birth, so the test file has no clock in it.
final DateTime _dob = DateTime(1994, 9, 4);
