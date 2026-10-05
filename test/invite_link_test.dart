import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shield/module/refer/invite_link.dart';

void main() {
  group('inviteCodeFrom', () {
    test('a bare code is the code', () {
      expect(inviteCodeFrom('SAHAKAR-8580'), 'SAHAKAR-8580');
      expect(inviteCodeFrom('  sahakar-8580 '), 'SAHAKAR-8580');
    });

    test('a Play referrer query string gives its referrer value', () {
      expect(inviteCodeFrom('utm_source=google-play&referrer=SAHAKAR-8580'), 'SAHAKAR-8580');
      expect(inviteCodeFrom('referrer=SAHAKAR-8580&utm_medium=share'), 'SAHAKAR-8580');
    });

    test('a web link gives the bare value under ref', () {
      expect(inviteCodeFrom('SAHAKAR-8580'), 'SAHAKAR-8580');
    });

    test('an organic install with no invite in it gives nothing', () {
      expect(inviteCodeFrom('utm_source=google-play&utm_medium=organic'), isNull);
      expect(inviteCodeFrom(''), isNull);
      expect(inviteCodeFrom(null), isNull);
    });

    test('something that cannot be a code is refused, not passed on', () {
      expect(inviteCodeFrom('not a code!'), isNull);
      expect(inviteCodeFrom('x'), isNull);
    });
  });

  group('inviteLinkFor', () {
    test('points at this app\'s Play listing and carries the code as referrer', () {
      final link = inviteLinkFor('SAHAKAR-8580');
      expect(link.host, 'play.google.com');
      expect(link.path, '/store/apps/details');
      expect(link.queryParameters['id'], appPackageId);
      expect(link.queryParameters['referrer'], 'SAHAKAR-8580');
    });

    test('the code it carries reads back out the same way the install does', () {
      final link = inviteLinkFor('SAHAKAR-8580');
      final referrer = link.queryParameters['referrer'];
      expect(inviteCodeFrom(referrer), 'SAHAKAR-8580');
    });
  });

  group('InstallReferrer', () {
    test('a code already remembered is handed back without asking the platform again', () async {
      SharedPreferences.setMockInitialValues({'install_invite_code': 'SAHAKAR-8580'});
      expect(await InstallReferrer.instance.code(), 'SAHAKAR-8580');
    });

    test('forgetting the code means it is not offered again', () async {
      SharedPreferences.setMockInitialValues({
        'install_invite_code': 'SAHAKAR-8580',
        'install_invite_read': true,
      });
      expect(await InstallReferrer.instance.code(), 'SAHAKAR-8580');
      await InstallReferrer.instance.forget();
      expect(await InstallReferrer.instance.code(), isNull);
    });

    test('with no platform answer (as in a plain test run) it reads as no code, not an error', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await InstallReferrer.instance.code(), isNull);
    });
  });
}
