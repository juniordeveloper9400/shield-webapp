import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shield/data/backend/backend_http.dart';
import 'package:shield/data/backend/registration_repository.dart';
import 'package:shield/module/registration/registration_service.dart';

void main() {
  MemberRepository repoFor(
    Future<http.Response> Function(http.Request request) handler,
  ) => MemberRepository.test(
    http: BackendHttp.test(client: MockClient(handler)),
  );

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  final registered = <String, dynamic>{
    'name': 'Asha',
    'email': 'asha@example.com',
    'gender': 'FEMALE',
    'dob': '1994-09-04',
    'address': '1 Main St',
    'place': 'Melattur',
    'pincode': '679326',
    'state': 'Kerala',
    'homeStoreId': 7,
    'homeStoreCode': 'SHD-MEL',
    'registrationCompletedAt': '2026-09-01T10:00:00.000Z',
  };

  group('fetchRegistration', () {
    test('registered: the profile and the branch code come back, even for a branch that is switched off', () async {
      // The public store list only carries active branches — this must not need it.
      var storeListAsked = false;
      final repo = repoFor((request) async {
        if (request.url.path == '/v1/public/catalogue/stores') {
          storeListAsked = true;
          return json([]);
        }
        expect(request.url.path, '/v1/member/me');
        return json(registered);
      });

      final lookup = await repo.fetchRegistration('9876543210');

      expect(lookup.status, RegistrationLookupStatus.registered);
      expect(lookup.registration?.storeId, 'SHD-MEL');
      expect(lookup.registration?.name, 'Asha');
      expect(lookup.registration?.phone, '9876543210');
      expect(lookup.registration?.gender, Gender.female);
      expect(lookup.registration?.dob, DateTime(1994, 9, 4));
      expect(storeListAsked, isFalse);
    });

    test('not registered: only when the backend says registrationCompletedAt is null', () async {
      final repo = repoFor(
        (_) async => json({...registered, 'registrationCompletedAt': null}),
      );

      final lookup = await repo.fetchRegistration('9876543210');

      expect(lookup.status, RegistrationLookupStatus.notRegistered);
      expect(lookup.registration, isNull);
    });

    test('registered stays registered when the branch or date of birth is missing', () async {
      // The bug: a registered member with no resolvable branch was reported as not registered.
      final repo = repoFor(
        (_) async => json({
          ...registered,
          'homeStoreId': null,
          'homeStoreCode': null,
          'dob': null,
        }),
      );

      final lookup = await repo.fetchRegistration('9876543210');

      expect(lookup.status, RegistrationLookupStatus.registered);
      expect(lookup.registration?.storeId, '');
      expect(lookup.registration?.store, isNull);
    });

    test('an older backend that only sends the numeric branch id still resolves it', () async {
      final repo = repoFor((request) async {
        if (request.url.path == '/v1/public/catalogue/stores') {
          return json([
            {'id': 7, 'code': 'SHD-MEL'},
          ]);
        }
        return json({...registered}..remove('homeStoreCode'));
      });

      final lookup = await repo.fetchRegistration('9876543210');

      expect(lookup.registration?.storeId, 'SHD-MEL');
    });

    test('a failed request is "unavailable" — never "not registered"', () async {
      for (final status in [401, 500, 503]) {
        final repo = repoFor(
          (_) async => json({
            'error': {'code': 'X', 'message': 'nope'},
          }, status),
        );
        final lookup = await repo.fetchRegistration('9876543210');
        expect(
          lookup.status,
          RegistrationLookupStatus.unavailable,
          reason: 'HTTP $status',
        );
      }
      final offline = repoFor((_) async => throw http.ClientException('offline'));
      expect(
        (await offline.fetchRegistration('9876543210')).status,
        RegistrationLookupStatus.unavailable,
      );
    });

    test('with no backend configured there is nothing to read', () async {
      // The singleton in a `flutter test` run is unconfigured.
      final lookup = await MemberRepository.instance.fetchRegistration('9876543210');
      expect(lookup.status, RegistrationLookupStatus.unavailable);
    });
  });

  group('upsertRegistration', () {
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

    test('sends the branch by its code, and needs no store list lookup to do it', () async {
      Map<String, dynamic>? sent;
      var otherRequests = 0;
      final repo = repoFor((request) async {
        if (request.method == 'PATCH') {
          expect(request.url.path, '/v1/member/me');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return json(registered);
        }
        otherRequests++;
        return json([]);
      });

      await repo.upsertRegistration(asha);

      expect(sent?['homeStoreCode'], 'SHD-MEL');
      expect(sent, isNot(contains('homeStoreId')));
      expect(sent?['name'], 'Asha');
      expect(sent?['dob'], '1994-09-04');
      expect(sent?['gender'], 'FEMALE');
      expect(sent?['email'], 'asha@example.com');
      expect(otherRequests, 0); // never silently drops the branch because a list was empty
    });

    test('leaves the branch out only when there genuinely is none', () async {
      Map<String, dynamic>? sent;
      final repo = repoFor((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json(registered);
      });

      await repo.upsertRegistration(asha.copyWith(storeId: ''));

      expect(sent, isNot(contains('homeStoreCode')));
    });

    test('a branch that is not taking new members: the backend’s own message is what the member sees', () async {
      final repo = repoFor(
        (_) async => json({
          'error': {
            'code': 'STORE_UNAVAILABLE',
            'message': "That branch isn't taking new registrations right now. Choose another branch.",
          },
        }, 403),
      );

      await expectLater(
        repo.upsertRegistration(asha),
        throwsA(
          isA<RegistrationSaveException>()
              .having((e) => e.code, 'code', 'STORE_UNAVAILABLE')
              .having((e) => e.message, 'message', contains('Choose another branch')),
        ),
      );
    });

    test('other refusals and an unreachable backend become plain, actionable messages', () async {
      final expired = repoFor(
        (_) async => json({
          'error': {'code': 'UNAUTHORIZED', 'message': 'x'},
        }, 401),
      );
      await expectLater(
        expired.upsertRegistration(asha),
        throwsA(isA<RegistrationSaveException>().having((e) => e.message, 'message', contains('Sign in again'))),
      );

      final throttled = repoFor(
        (_) async => json({
          'error': {'code': 'TOO_MANY_REQUESTS', 'message': 'x'},
        }, 429),
      );
      await expectLater(
        throttled.upsertRegistration(asha),
        throwsA(isA<RegistrationSaveException>().having((e) => e.message, 'message', contains('Too many attempts'))),
      );

      final offline = repoFor((_) async => throw http.ClientException('offline'));
      await expectLater(
        offline.upsertRegistration(asha),
        throwsA(isA<RegistrationSaveException>().having((e) => e.message, 'message', contains('Check your connection'))),
      );
    });

    test('does nothing when there is no backend, as before', () async {
      await MemberRepository.instance.upsertRegistration(asha); // no throw
    });
  });
}
