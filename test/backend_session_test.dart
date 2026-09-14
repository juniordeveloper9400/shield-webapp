import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shield/data/backend/backend_http.dart';
import 'package:shield/data/backend/backend_session.dart';

void main() {
  group('BackendSession.signInWithFirebaseToken', () {
    test('signs in directly when the session route recognizes the identity', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/member/auth/session');
        expect(jsonDecode(request.body), {'idToken': 'token-1'});
        return http.Response(
          jsonEncode({'accessToken': 'access-1', 'refreshToken': 'refresh-1', 'expiresIn': 900}),
          200,
        );
      });
      final http_ = BackendHttp.test(client: client);
      final session = BackendSession.test(http: http_);

      final result = await session.signInWithFirebaseToken('token-1', name: 'Rahul Nair');

      expect(result, isTrue);
      expect(http_.isSignedIn, isTrue);
    });

    test('falls back to registering a new identity on a 404 from the session route', () async {
      final calledPaths = <String>[];
      final client = MockClient((request) async {
        calledPaths.add(request.url.path);
        if (request.url.path == '/v1/member/auth/session') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'NOT_FOUND', 'message': 'No member registered for this identity yet'},
            }),
            404,
          );
        }
        expect(request.url.path, '/v1/member/auth/register');
        expect(jsonDecode(request.body), {'idToken': 'token-2', 'name': 'Brand New Member'});
        return http.Response(
          jsonEncode({'accessToken': 'access-2', 'refreshToken': 'refresh-2', 'expiresIn': 900}),
          200,
        );
      });
      final http_ = BackendHttp.test(client: client);
      final session = BackendSession.test(http: http_);

      final result = await session.signInWithFirebaseToken('token-2', name: 'Brand New Member');

      expect(result, isTrue);
      expect(http_.isSignedIn, isTrue);
      expect(calledPaths, ['/v1/member/auth/session', '/v1/member/auth/register']);
    });

    test('returns false without throwing when both the session and register calls fail', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid or expired token'},
          }),
          401,
        ),
      );
      final session = BackendSession.test(http: BackendHttp.test(client: client));

      final result = await session.signInWithFirebaseToken('bad-token', name: 'Someone');

      expect(result, isFalse);
    });
  });

  group('BackendSession.signOut', () {
    test('clears the local session even when the revoke call itself fails', () async {
      final client = MockClient((request) async => http.Response('server error', 500));
      final http_ = BackendHttp.test(client: client);
      await http_.setSession(accessToken: 'access', refreshToken: 'refresh');
      final session = BackendSession.test(http: http_);

      await session.signOut();

      expect(http_.isSignedIn, isFalse);
    });
  });
}
