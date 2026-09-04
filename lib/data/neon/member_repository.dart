import 'neon_http.dart';

/// Writes the signed-in user to the `app.users` table on Neon and reads back
/// the little the app needs from it.
///
/// Every method is best-effort: when the app was built without a `DATABASE_URL`
/// (tests, a build that left `--dart-define-from-file=.env` off) or the network
/// is down, the calls no-op and return null rather than throwing. Sign-in must
/// never fail because the database is unreachable — the Firebase session is the
/// source of truth for *whether* a user is in; this table is the record of
/// *who*.
///
/// Goes over [NeonHttp] (HTTPS) rather than the raw Postgres socket so it works
/// the same in a release build.
class MemberRepository {
  const MemberRepository._();

  static const MemberRepository instance = MemberRepository._();

  /// Whether a write would actually reach the database.
  bool get isAvailable => NeonHttp.isConfigured;

  /// Inserts the user on first sign-in, or refreshes their name,
  /// `firebase_uid` and `last_login_at` on a return sign-in. Keyed on the
  /// mobile number, which is unique in `app.users`.
  Future<void> upsertOnSignIn({
    required String name,
    required String phone,
    String? firebaseUid,
  }) async {
    await _run('upsertOnSignIn', () async {
      await NeonHttp.instance.query(
        '''
          INSERT INTO app.users (phone, name, firebase_uid, last_login_at)
          VALUES (\$1, \$2, \$3, now())
          ON CONFLICT (phone) DO UPDATE SET
            name          = EXCLUDED.name,
            firebase_uid  = COALESCE(EXCLUDED.firebase_uid, app.users.firebase_uid),
            last_login_at = now(),
            updated_at    = now()
        ''',
        [phone, name, firebaseUid],
      );
      NeonHttp.log('upsertOnSignIn: saved $phone');
    });
  }

  /// Whether an `app.users` row exists for [phone] — i.e. this number has
  /// signed in before and has an account. `null` when the check could not run
  /// (no `DATABASE_URL`, or the network is down), so a caller can fall open
  /// rather than block a real member on a blip.
  Future<bool?> phoneExists(String phone) {
    return _run('phoneExists', () async {
      final rows = await NeonHttp.instance.query(
        'SELECT 1 FROM app.users WHERE phone = \$1 AND deleted_at IS NULL LIMIT 1',
        [phone],
      );
      return rows.isNotEmpty;
    });
  }

  /// The stored name for [phone], used at launch when the Firebase profile
  /// carries no display name. Null when there is no row or the lookup failed.
  Future<String?> nameByPhone(String phone) async {
    return _run('nameByPhone', () async {
      final rows = await NeonHttp.instance.query(
        'SELECT name FROM app.users WHERE phone = \$1 LIMIT 1',
        [phone],
      );
      if (rows.isEmpty) {
        return null;
      }
      final value = rows.first['name'];
      return value is String && value.trim().isNotEmpty ? value : null;
    });
  }

  /// Bumps `last_login_at` for a session restored at launch, so the column
  /// tracks real app opens and not just fresh OTP sign-ins.
  Future<void> touchLogin(String phone) async {
    await _run('touchLogin', () async {
      await NeonHttp.instance.query(
        'UPDATE app.users SET last_login_at = now() WHERE phone = \$1',
        [phone],
      );
    });
  }

  /// Runs [action], swallowing everything: a missing `DATABASE_URL`, a network
  /// error, a SQL error. Returns null on any of them.
  Future<T?> _run<T>(String label, Future<T?> Function() action) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      return await action();
    } catch (error) {
      NeonHttp.log('MemberRepository.$label failed', error: error);
      return null;
    }
  }
}
