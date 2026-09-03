import '../../data/neon/neon_http.dart';
import 'registration_service.dart';

/// Persists the user profile behind a completed registration to Neon
/// (`app.users`), over the HTTP SQL endpoint.
///
/// [RegistrationService] stays the in-memory source of truth the UI listens to;
/// this is the write-through. It is a no-op when the app was built without a
/// `DATABASE_URL` (tests, or a build that left `--dart-define-from-file=.env`
/// off — see [NeonHttp.isConfigured]), so the registration flow keeps working
/// with or without a backend.
class MemberRepository {
  MemberRepository._();

  static final MemberRepository instance = MemberRepository._();

  /// Whether a write would actually reach a database.
  bool get isAvailable => NeonHttp.isConfigured;

  /// Inserts the member, or updates the existing row with the same [phone].
  ///
  /// Identity is the 10-digit mobile number (`app.users.phone` is unique and
  /// carries no `+91`). The assigned branch is resolved from
  /// [Registration.storeId] — the app's stable store code — to the
  /// `app.shield_store` primary key.
  ///
  /// `reward_points` is not written here — the reward-points ledger
  /// (`app.reward_point_transaction`, via `RewardsRepository`) owns that column
  /// and moves it on the registration bonus.
  ///
  /// Throws if the write fails; callers decide whether that is fatal.
  Future<void> upsertRegistration(Registration registration) async {
    if (!isAvailable) {
      return;
    }

    await NeonHttp.instance.query(
      '''
        INSERT INTO app.users (
          phone, name, email, gender, dob,
          address, place, pincode, state,
          home_store_id, registration_completed_at
        )
        VALUES (
          \$1, \$2, \$3, \$4::app.gender, \$5::date,
          \$6, \$7, \$8, \$9,
          (SELECT id FROM app.shield_store WHERE code = \$10),
          now()
        )
        ON CONFLICT (phone) DO UPDATE SET
          name                      = EXCLUDED.name,
          email                     = EXCLUDED.email,
          gender                    = EXCLUDED.gender,
          dob                       = EXCLUDED.dob,
          address                   = EXCLUDED.address,
          place                     = EXCLUDED.place,
          pincode                   = EXCLUDED.pincode,
          state                     = EXCLUDED.state,
          home_store_id             = EXCLUDED.home_store_id,
          registration_completed_at = COALESCE(
            app.users.registration_completed_at,
            EXCLUDED.registration_completed_at
          )
      ''',
      [
        registration.phone,
        registration.name,
        registration.email.isEmpty ? null : registration.email,
        registration.gender.name.toUpperCase(),
        _isoDate(registration.dob),
        registration.address,
        registration.place,
        registration.pincode,
        registration.state,
        registration.storeId,
      ],
    );
    NeonHttp.log('upsertRegistration: saved ${registration.phone}');
  }

  /// `1994-09-04` — an unambiguous value for a `date` column.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
