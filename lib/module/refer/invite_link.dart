import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Play Store listing this app is published under. The invite link a
/// member shares points at this listing and nowhere else.
const String appPackageId = 'com.zabnix.shield';

/// The link a member shares to invite someone.
///
/// On Android this is the app's Play Store listing with the member's own invite
/// code riding along as Play's `referrer` parameter. Play hands that value back
/// to the app on its first launch after install ([InstallReferrer]), so the
/// registration form fills in the Referral ID without the friend typing it.
///
/// On the web the same code travels as `?ref=` on the address the app is served
/// from, read back the same way on the first load.
Uri inviteLinkFor(String code) {
  if (kIsWeb) {
    return Uri.base.replace(path: '/', queryParameters: {'ref': code});
  }
  return Uri.https('play.google.com', '/store/apps/details', {
    'id': appPackageId,
    'referrer': code,
  });
}

/// Pulls an invite code out of whatever an install or a link carried in.
///
/// Play passes the raw referrer string, which is either the bare code or a query
/// string such as `utm_source=x&referrer=CODE`. A web link gives the bare code
/// under `ref`. Returns null when nothing in it looks like an invite code.
String? inviteCodeFrom(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  String? candidate;
  if (text.contains('=')) {
    final params = Uri.splitQueryString(text);
    for (final key in const ['referrer', 'ref', 'referral', 'code']) {
      final value = params[key]?.trim();
      if (value != null && value.isNotEmpty) {
        candidate = value;
        break;
      }
    }
  } else {
    candidate = text;
  }
  final code = candidate?.toUpperCase();
  if (code == null || !_codeShape.hasMatch(code)) {
    return null;
  }
  return code;
}

final RegExp _codeShape = RegExp(r'^[A-Z0-9][A-Z0-9-]{2,39}$');

/// The invite code this install came in on, read once and remembered.
///
/// On Android the code comes from the Play install referrer, read only on the
/// first launch after install. On the web it comes from the `ref` parameter of
/// the address the app was opened on. Best-effort throughout: anything that
/// goes wrong reads as "no invite code", never as an error on the form.
class InstallReferrer {
  InstallReferrer._();

  static final InstallReferrer instance = InstallReferrer._();

  static const _codeKey = 'install_invite_code';
  static const _readKey = 'install_invite_read';

  Future<String?>? _pending;

  /// The invite code this install came in on, or null when it did not come in
  /// on one. Memoised, so the platform is asked at most once per app session.
  Future<String?> code() => _pending ??= _read();

  /// Forgets the remembered code, once the registration that used it has been
  /// submitted, so a later visit to the form does not offer it again.
  Future<void> forget() async {
    _pending = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_codeKey);
    } catch (_) {
      // Nothing to forget if storage is unavailable.
    }
  }

  Future<String?> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (kIsWeb) {
        final fromLink = inviteCodeFrom(Uri.base.queryParameters['ref']);
        if (fromLink != null) {
          await prefs.setString(_codeKey, fromLink);
          return fromLink;
        }
        return prefs.getString(_codeKey);
      }

      final saved = prefs.getString(_codeKey);
      if (saved != null || (prefs.getBool(_readKey) ?? false)) {
        return saved;
      }
      if (defaultTargetPlatform != TargetPlatform.android) {
        return null;
      }
      final details = await AndroidPlayInstallReferrer.installReferrer;
      final found = inviteCodeFrom(details.installReferrer);
      // Marked read only once Play actually answered, so a launch with Play
      // services unavailable gets another try next time.
      await prefs.setBool(_readKey, true);
      if (found != null) {
        await prefs.setString(_codeKey, found);
      }
      return found;
    } catch (_) {
      return null;
    }
  }
}
