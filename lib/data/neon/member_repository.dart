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
  ///
  /// Also clears `deleted_at`: the only way this conflicts against an
  /// existing row for a *deleted* account is a member who deleted their
  /// account and is now signing up fresh on the same number — see
  /// [deleteAccount] — and that is a real reactivation, not a database
  /// artefact left over from before. Leaving `deleted_at` set here would
  /// strand them permanently invisible to [phoneExists] despite a working
  /// session.
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
            updated_at    = now(),
            deleted_at    = NULL
        ''',
        [phone, name, firebaseUid],
      );
      NeonHttp.log('upsertOnSignIn: saved $phone');
    });
  }

  /// Deletes the member's account: soft — `deleted_at` is stamped rather than
  /// the row removed, so `app."order"`/`app.wallet`/every other table with an
  /// `ON DELETE CASCADE`/`SET NULL` FK to `app.users(id)` keeps its history
  /// intact for accounting rather than being silently wiped or orphaned —
  /// and the personal fields on the row itself are cleared, since a member
  /// who asked to be deleted should not have their name/DOB/address still
  /// sitting there just because the row lives on for its order history.
  /// `phone` is kept: it is the unique key [upsertOnSignIn] re-activates
  /// against if this same member signs up again later, and every existing
  /// order/receipt still reads back to *a* real number rather than a blank.
  ///
  /// Deliberately more than the admin console's own `deleteUser`
  /// (`shieldweb/src/api/users.ts`), which only ever stamps `deleted_at` —
  /// an admin revoking access may need the full record intact (a
  /// suspension, a dispute), where a member's own "delete my account" is a
  /// privacy request the fields themselves should not survive. Both read as
  /// the exact same `deleted_at` on the shared database.
  ///
  /// Best-effort like every other write here — see the class doc. Returns
  /// whether the update actually touched a row, so the caller can tell a
  /// real deletion from "there was nothing to delete" (no `DATABASE_URL`, or
  /// the phone was never signed up).
  Future<bool> deleteAccount(String phone) async {
    final result = await _run('deleteAccount', () async {
      final rows = await NeonHttp.instance.query(
        '''
          UPDATE app.users
          SET name = 'Deleted user',
              email = NULL,
              gender = NULL,
              dob = NULL,
              address = NULL,
              place = NULL,
              pincode = NULL,
              state = NULL,
              firebase_uid = NULL,
              deleted_at = now(),
              updated_at = now()
          WHERE phone = \$1 AND deleted_at IS NULL
          RETURNING id
        ''',
        [phone],
      );
      return rows.isNotEmpty;
    });
    return result ?? false;
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
