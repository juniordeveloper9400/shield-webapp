import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shield/data/backend/backend_http.dart';

void main() {
  group('BackendHttp', () {
    test('returns the decoded JSON body on a 2xx response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/agent/team');
        return http.Response(jsonEncode({'id': 1, 'name': 'National'}), 200);
      });
      final backend = BackendHttp.test(client: client);

      final result = await backend.request('GET', '/v1/agent/team');

      expect(result, {'id': 1, 'name': 'National'});
    });

    test('returns null for a 204 No Content response', () async {
      final client = MockClient((request) async => http.Response('', 204));
      final backend = BackendHttp.test(client: client);

      final result = await backend.request('DELETE', '/v1/member/auth/session');

      expect(result, isNull);
    });

    test('throws BackendHttpException with the parsed error envelope on a non-2xx response', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {'code': 'FORBIDDEN', 'message': 'Not an approved agent'},
          }),
          403,
        ),
      );
      final backend = BackendHttp.test(client: client);

      await expectLater(
        () => backend.request('GET', '/v1/agent/team'),
        throwsA(
          isA<BackendHttpException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'FORBIDDEN')
              .having((e) => e.isForbidden, 'isForbidden', isTrue),
        ),
      );
    });

    test('silently refreshes once and retries after a 401, then succeeds', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        if (request.url.path == '/v1/member/auth/refresh') {
          expect(jsonDecode(request.body), {'refreshToken': 'old-refresh'});
          return http.Response(
            jsonEncode({'accessToken': 'new-access', 'refreshToken': 'new-refresh', 'expiresIn': 900}),
            200,
          );
        }
        // The protected route: unauthorized on the first try (stale token),
        // then succeeds once the retry carries the freshly refreshed one.
        final authHeader = request.headers['Authorization'];
        if (authHeader == 'Bearer new-access') {
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response(jsonEncode({'error': {'code': 'UNAUTHORIZED', 'message': 'expired'}}), 401);
      });
      final backend = BackendHttp.test(client: client);
      await backend.setSession(accessToken: 'stale-access', refreshToken: 'old-refresh');

      final result = await backend.request('GET', '/v1/member/wallet');

      expect(result, {'ok': true});
      expect(callCount, 3); // 401 attempt, refresh, retry
    });

    test('coalesces concurrent 401s into a single refresh call — the backend rotates refresh tokens, so a second concurrent refresh attempt would fail', () async {
      var refreshCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/v1/member/auth/refresh') {
          refreshCalls++;
          // A real backend would reject a second concurrent call with this
          // same (now-rotated) refresh token — returning success unconditionally
          // here would hide exactly the bug this test exists to catch.
          expect(refreshCalls, 1, reason: 'refresh token is single-use; a second call here means the race was not coalesced');
          return http.Response(
            jsonEncode({'accessToken': 'new-access', 'refreshToken': 'new-refresh', 'expiresIn': 900}),
            200,
          );
        }
        final authHeader = request.headers['Authorization'];
        if (authHeader == 'Bearer new-access') {
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response(jsonEncode({'error': {'code': 'UNAUTHORIZED', 'message': 'expired'}}), 401);
      });
      final backend = BackendHttp.test(client: client);
      await backend.setSession(accessToken: 'stale-access', refreshToken: 'old-refresh');

      // Several requests firing in parallel with an already-stale access
      // token — the exact shape of a page load that fetches persona,
      // patients and rewards at once.
      final results = await Future.wait([
        backend.request('GET', '/v1/member/wallet'),
        backend.request('GET', '/v1/member/patients'),
        backend.request('GET', '/v1/member/rewards/transactions'),
      ]);

      expect(results, everyElement({'ok': true}));
      expect(refreshCalls, 1);
    });

    test('gives up after a 401 whose refresh also fails, without retrying again', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/v1/member/auth/refresh') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'UNAUTHORIZED', 'message': 'Refresh token invalid or expired'},
            }),
            401,
          );
        }
        attempts++;
        return http.Response(jsonEncode({'error': {'code': 'UNAUTHORIZED', 'message': 'expired'}}), 401);
      });
      final backend = BackendHttp.test(client: client);
      await backend.setSession(accessToken: 'stale-access', refreshToken: 'dead-refresh');

      await expectLater(
        () => backend.request('GET', '/v1/member/wallet'),
        throwsA(isA<BackendHttpException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(attempts, 1); // no second retry once the refresh itself failed
    });
  });
}
