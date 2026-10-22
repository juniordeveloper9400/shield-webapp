import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:shield/data/backend/backend_http.dart';
import 'package:shield/data/backend/backend_session.dart';

void main() {
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
