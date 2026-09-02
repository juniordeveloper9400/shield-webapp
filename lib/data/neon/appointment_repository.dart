import 'neon_http.dart';

/// The four kinds of appointment a member can book — mirrors
/// `app.appointment_kind`.
enum AppointmentKind { clinic, tele, dental, dietitian }

/// Writes a member's appointment booking to the `app.appointment` table on
/// Neon.
///
/// Best-effort, the same contract as the other repositories: no `DATABASE_URL`
/// (tests, a build without `--dart-define-from-file=.env`) or an unreachable
/// endpoint → the call no-ops. Booking is an offer, not a gate.
///
/// Goes over [NeonHttp] (HTTPS on 443), so it works from a `flutter build web`
/// bundle as well as the APK. `app.appointment.member_id` is `NOT NULL`, so
/// [book] upserts the owning `app.users` row (by phone) in the same CTE
/// statement; `clinic_id` / `dietitian_id` are resolved by name and left null
/// when there is no match.
class AppointmentRepository {
  const AppointmentRepository._();

  static const AppointmentRepository instance = AppointmentRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// Records a `REQUESTED` appointment (the `status` column default).
  ///
  /// The app books against plain-word slots ("Today, 4:00 PM"), not real
  /// timestamps, so [scheduledFor] is usually null and the wording is carried
  /// in [remarks] instead.
  ///
  /// Returns the `app.appointment` row's `uuid`, or null when nothing was
  /// written.
  Future<String?> book({
    required String memberPhone,
    required String memberName,
    required AppointmentKind kind,
    String? clinicName,
    String? dietitianName,
    String? doctorName,
    num? fee,
    DateTime? scheduledFor,
    String remarks = '',
  }) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await NeonHttp.instance.query(
        '''
          WITH owner AS (
            INSERT INTO app.users (phone, name)
            VALUES (\$1, \$2)
            ON CONFLICT (phone) DO UPDATE SET updated_at = now()
            RETURNING id
          )
          INSERT INTO app.appointment
            (member_id, kind, clinic_id, dietitian_id, doctor_name, fee,
             scheduled_for, remarks)
          SELECT owner.id,
                 \$3::app.appointment_kind,
                 (SELECT id FROM app.clinic    WHERE name = \$4),
                 (SELECT id FROM app.dietitian WHERE name = \$5),
                 \$6, \$7, \$8, \$9
          FROM owner
          RETURNING uuid
        ''',
        [
          memberPhone,
          memberName,
          kind.name.toUpperCase(),
          clinicName,
          dietitianName,
          doctorName,
          fee,
          scheduledFor?.toUtc().toIso8601String(),
          remarks,
        ],
      );
      return rows.isEmpty ? null : rows.first['uuid']?.toString();
    } catch (error) {
      NeonHttp.log('AppointmentRepository.book failed', error: error);
      return null;
    }
  }
}
