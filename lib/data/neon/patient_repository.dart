import '../../module/patients/patient_book.dart';
import 'neon_http.dart';

/// Reads and writes the people on an account in the `app.patient` table on Neon,
/// over the HTTP SQL endpoint (see [NeonHttp]).
///
/// Every method is best-effort: with no `DATABASE_URL` compiled in (tests) or
/// the network down, writes no-op and reads return null. Adding a patient must
/// never fail because the database is unreachable — [PatientBook] stays the
/// source of truth for the running app, and this table is the durable copy that
/// is read back on the next launch.
///
/// `app.patient.member_id` is `NOT NULL`, so [upsert] resolves the owning
/// `app.users` row from the signed-in mobile number first, inserting a minimal
/// user if sign-in has not already written one.
class PatientRepository {
  const PatientRepository._();

  static const PatientRepository instance = PatientRepository._();

  /// Whether a write or read would actually reach the database.
  bool get isAvailable => NeonHttp.isConfigured;

  /// Inserts a new patient, or updates the existing row when [uuid] is given
  /// (the value a previous call returned, held on [Patient.remoteId]).
  ///
  /// Returns the row's `uuid` so the caller can pin it onto the in-memory
  /// record with [PatientBook.attachRemoteId]. Null when nothing was written.
  Future<String?> upsert({
    String? uuid,
    required String memberPhone,
    required String memberName,
    required String name,
    required String phone,
    required String address,
    required DateTime dob,
    required PatientGender gender,
    required PatientRelation relation,
    required String abhaId,
  }) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }

    final n = name.trim();
    final p = phone.trim();
    final addr = address.trim();
    final dobIso = _isoDate(dob);
    final g = gender.name.toUpperCase();
    final r = relation.name.toUpperCase();
    final abha = abhaId.replaceAll(RegExp(r'\D'), '');

    try {
      if (uuid != null) {
        final updated = await NeonHttp.instance.query(
          r'''
            UPDATE app.patient SET
              name       = $1,
              phone      = $2,
              address    = $3,
              dob        = $4::date,
              gender     = $5::app.gender,
              relation   = $6::app.patient_relation,
              abha_id    = $7,
              updated_at = now()
            WHERE uuid = $8::uuid AND deleted_at IS NULL
            RETURNING uuid
          ''',
          [n, p, addr, dobIso, g, r, abha, uuid],
        );
        if (updated.isNotEmpty) {
          return updated.first['uuid']?.toString();
        }
        // Row is gone (database wiped, or a stale id) — fall through and write a
        // fresh one rather than silently losing the patient.
      }

      final inserted = await NeonHttp.instance.query(
        r'''
          WITH owner AS (
            INSERT INTO app.users (phone, name)
            VALUES ($1, $2)
            ON CONFLICT (phone) DO UPDATE SET updated_at = now()
            RETURNING id
          )
          INSERT INTO app.patient
            (member_id, name, phone, address, dob, gender, relation, abha_id)
          SELECT owner.id, $3, $4, $5, $6::date,
                 $7::app.gender, $8::app.patient_relation, $9
          FROM owner
          RETURNING uuid
        ''',
        [memberPhone, memberName, n, p, addr, dobIso, g, r, abha],
      );
      final id = inserted.isEmpty ? null : inserted.first['uuid']?.toString();
      NeonHttp.log('PatientRepository.upsert: saved $n ($id)');
      return id;
    } catch (error) {
      NeonHttp.log('PatientRepository.upsert failed', error: error);
      return null;
    }
  }

  /// Marks a patient row soft-deleted (`deleted_at = now()`). A no-op when
  /// [uuid] is unknown.
  Future<void> softDelete(String uuid) async {
    if (!NeonHttp.isConfigured) {
      return;
    }
    try {
      await NeonHttp.instance.query(
        r'UPDATE app.patient SET deleted_at = now() '
        r'WHERE uuid = $1::uuid AND deleted_at IS NULL',
        [uuid],
      );
    } catch (error) {
      NeonHttp.log('PatientRepository.softDelete failed', error: error);
    }
  }

  /// Every non-deleted patient for the member with [memberPhone], oldest first.
  ///
  /// Returns `null` (not an empty list) when the database is off or unreachable,
  /// so the caller can tell "this account has no saved patients" from "could not
  /// load them" and avoid wiping the in-memory list on a transient failure.
  Future<List<Patient>?> listForMember(String memberPhone) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await NeonHttp.instance.query(
        r'''
          SELECT p.uuid, p.name, p.phone, p.address, p.dob,
                 p.gender::text   AS gender,
                 p.relation::text AS relation,
                 p.abha_id
          FROM app.patient p
          JOIN app.users u ON u.id = p.member_id
          WHERE u.phone = $1 AND p.deleted_at IS NULL
          ORDER BY p.created_at
        ''',
        [memberPhone],
      );
      return rows.map(_toPatient).toList();
    } catch (error) {
      NeonHttp.log('PatientRepository.listForMember failed', error: error);
      return null;
    }
  }

  /// One `app.patient` row → a [Patient]. The id is derived from the row `uuid`
  /// so a reload lands on the same in-memory record, and `remoteId` is set so
  /// [PatientBook] knows this one is already backed by the database.
  static Patient _toPatient(Map<String, dynamic> row) {
    final uuid = row['uuid']?.toString() ?? '';
    return Patient(
      id: 'remote-$uuid',
      remoteId: uuid.isEmpty ? null : uuid,
      name: (row['name'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      address: (row['address'] ?? '').toString(),
      dob: DateTime.tryParse((row['dob'] ?? '').toString()) ?? DateTime(2000),
      gender: _genderFrom(row['gender']?.toString()),
      relation: _relationFrom(row['relation']?.toString()),
      abhaId: (row['abha_id'] ?? '').toString(),
    );
  }

  static PatientGender _genderFrom(String? label) => PatientGender.values
      .firstWhere((g) => g.name.toUpperCase() == label,
          orElse: () => PatientGender.other);

  static PatientRelation _relationFrom(String? label) => PatientRelation.values
      .firstWhere((r) => r.name.toUpperCase() == label,
          orElse: () => PatientRelation.other);

  /// `1994-09-04` — an unambiguous value for a `date` column.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
