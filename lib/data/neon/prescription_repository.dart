import '../../module/patients/patient_book.dart';
import '../../module/prescription/medicine_duration.dart';
import '../../module/prescription/prescription_record.dart';
import 'neon_http.dart';

/// One prescription's pharmacist-built intake card, as read back from Neon.
class RemotePrescriptionCard {
  final String code;
  final String? uuid;

  /// `AWAITING_REVIEW` / `ORDERED` / `READ` — the console's own status trail.
  final String status;
  final String doctor;
  final List<RemotePrescriptionMedicine> medicines;

  RemotePrescriptionCard({
    required this.code,
    required this.uuid,
    required this.status,
    required this.doctor,
    required this.medicines,
  });

  /// The pharmacist has entered the lines — the app card can expand.
  bool get hasIntakeCard => medicines.isNotEmpty;
}

/// One line on a [RemotePrescriptionCard].
class RemotePrescriptionMedicine {
  final String name;
  final String pack;
  final int morning;
  final int afternoon;
  final int night;

  /// Units the pharmacist wrote for this line — entered in the console, not
  /// derived.
  final int totalUnits;

  const RemotePrescriptionMedicine({
    required this.name,
    required this.pack,
    required this.morning,
    required this.afternoon,
    required this.night,
    required this.totalUnits,
  });
}

/// Writes an uploaded prescription to the `app.prescription` (and
/// `app.prescription_medicine`) tables on Neon.
///
/// Every method is best-effort: when the app was built without a `DATABASE_URL`
/// (tests, a build that left `--dart-define-from-file=.env` off) or the network
/// is down, the call no-ops and returns null rather than throwing. Uploading a
/// prescription must never fail because the database is unreachable —
/// [PrescriptionBook] stays the source of truth for the running app, and this
/// row is the durable copy.
///
/// Goes over [NeonHttp] (HTTPS on 443) rather than the raw Postgres socket so it
/// behaves identically in a `--release` build. Neon's `/sql` endpoint runs one
/// statement per request with no client transaction, so the owning `app.users`
/// row, the `app.patient` and the prescription itself are written in dependency
/// order, and the medicine lines go in as one set-based statement.
class PrescriptionRepository {
  const PrescriptionRepository._();

  static const PrescriptionRepository instance = PrescriptionRepository._();

  /// Records a freshly uploaded prescription. The counter fills the doctor and
  /// medicines later, so those are usually empty here and the row lands as
  /// `AWAITING_REVIEW` (the column default).
  ///
  /// Returns the `app.prescription` row's `uuid`, or null when nothing was
  /// written.
  Future<String?> insertUpload({
    required String memberPhone,
    required String memberName,
    String? patientUuid,
    required String patientName,
    required String patientPhone,
    required String patientAddress,
    required DateTime patientDob,
    required PatientGender patientGender,
    required PatientRelation patientRelation,
    required String patientAbhaId,
    required String code,
    required String fileName,
    String? image,
    String? storeCode,
    String doctor = '',
    MedicineDuration? duration,
    int? customDays,
    DateTime? recurringFrom,
    DateTime? recurringUntil,
    List<PrescriptionMedicine> medicines = const [],
  }) {
    return _run('insertUpload', () async {
      // 1 · The owning account — insert a minimal row if sign-in has not
      // already written one.
      final ownerRows = await NeonHttp.instance.query(
        '''
          INSERT INTO app.users (phone, name)
          VALUES (\$1, \$2)
          ON CONFLICT (phone) DO UPDATE SET updated_at = now()
          RETURNING id
        ''',
        [memberPhone, memberName],
      );
      final memberId = _rowId(ownerRows);
      if (memberId == null) {
        return null;
      }

      // 2 · The patient the prescription is for. Prefer the row a previous
      // PatientRepository write pinned onto the record; otherwise insert one
      // against this account.
      int? patientId;
      if (patientUuid != null && patientUuid.isNotEmpty) {
        final found = await NeonHttp.instance.query(
          '''
            SELECT id FROM app.patient
            WHERE uuid = \$1::uuid AND deleted_at IS NULL
          ''',
          [patientUuid],
        );
        patientId = _rowId(found);
      }
      patientId ??= _rowId(
        await NeonHttp.instance.query(
          '''
            INSERT INTO app.patient
              (member_id, name, phone, address, dob, gender, relation, abha_id)
            VALUES
              (\$1, \$2, \$3, \$4, \$5::date,
               \$6::app.gender, \$7::app.patient_relation, \$8)
            RETURNING id
          ''',
          [
            memberId,
            patientName.trim(),
            patientPhone.trim(),
            patientAddress.trim(),
            _isoDate(patientDob),
            patientGender.name.toUpperCase(),
            patientRelation.name.toUpperCase(),
            patientAbhaId.replaceAll(RegExp(r'\D'), ''),
          ],
        ),
      );
      if (patientId == null) {
        return null;
      }

      // 3 · The prescription. status defaults to 'AWAITING_REVIEW'.
      final inserted = await NeonHttp.instance.query(
        '''
          INSERT INTO app.prescription
            (member_id, patient_id, store_id, code, file_name, image, doctor,
             duration, custom_days, recurring_from, recurring_until)
          VALUES
            (\$1, \$2,
             (SELECT id FROM app.shield_store WHERE code = \$3),
             \$4, \$5, \$6, \$7,
             \$8::app.medicine_duration, \$9,
             \$10::date, \$11::date)
          RETURNING id, uuid
        ''',
        [
          memberId,
          patientId,
          storeCode,
          code,
          fileName,
          image,
          doctor,
          _durationName(duration),
          customDays,
          _isoDate(recurringFrom),
          _isoDate(recurringUntil),
        ],
      );
      if (inserted.isEmpty) {
        return null;
      }
      final prescriptionId = _rowId(inserted);
      final prescriptionUuid = inserted.first['uuid']?.toString();
      if (prescriptionId == null) {
        return null;
      }

      // 4 · Any medicine lines already keyed in (usually none at upload — the
      // pharmacy counter adds them afterwards).
      await _insertMedicines(prescriptionId, medicines);

      return prescriptionUuid;
    });
  }

  /// Writes back what the counter read off the script: the prescriber and the
  /// medicine lines, moving an `AWAITING_REVIEW` row to `READ`. Mirrors
  /// [PrescriptionBook.fillFromPharmacy] on the database side.
  ///
  /// The row is found by [prescriptionUuid] when the app pinned one at upload,
  /// otherwise by the member's most recent non-ordered script with this
  /// [fileName]. A no-op when neither resolves.
  Future<void> syncPharmacyRead({
    required String memberPhone,
    String? prescriptionUuid,
    required String fileName,
    required String doctor,
    List<PrescriptionMedicine> medicines = const [],
  }) async {
    await _run<Object?>('syncPharmacyRead', () async {
      int? prescriptionId;
      if (prescriptionUuid != null && prescriptionUuid.isNotEmpty) {
        final byUuid = await NeonHttp.instance.query(
          'SELECT id FROM app.prescription '
          'WHERE uuid = \$1::uuid AND deleted_at IS NULL',
          [prescriptionUuid],
        );
        prescriptionId = _rowId(byUuid);
      }
      if (prescriptionId == null) {
        final byFile = await NeonHttp.instance.query(
          '''
            SELECT rx.id FROM app.prescription rx
            JOIN app.users u ON u.id = rx.member_id
            WHERE u.phone = \$1
              AND rx.file_name = \$2
              AND rx.status <> 'ORDERED'
              AND rx.deleted_at IS NULL
            ORDER BY rx.created_at DESC
            LIMIT 1
          ''',
          [memberPhone, fileName],
        );
        prescriptionId = _rowId(byFile);
        if (prescriptionId == null) {
          return null;
        }
      }

      await NeonHttp.instance.query(
        '''
          UPDATE app.prescription SET
            doctor      = CASE WHEN \$2 <> '' THEN \$2 ELSE doctor END,
            status      = CASE WHEN status = 'AWAITING_REVIEW'
                               THEN 'READ'::app.prescription_status
                               ELSE status END,
            reviewed_at = COALESCE(reviewed_at, now()),
            updated_at  = now()
          WHERE id = \$1
        ''',
        [prescriptionId, doctor],
      );

      await NeonHttp.instance.query(
        'DELETE FROM app.prescription_medicine WHERE prescription_id = \$1',
        [prescriptionId],
      );
      await _insertMedicines(prescriptionId, medicines);
      return null;
    });
  }

  /// The pharmacist-built intake cards for every prescription on the account.
  ///
  /// The app reads this when the prescription screen opens and on pull-to-
  /// refresh: an uploaded script starts with no medicine lines, the counter
  /// adds them in the console, and the card on the screen expands the next
  /// time this is read. Returns null when the database is off or unreachable
  /// (so "not loaded" reads differently from "nothing sent yet").
  ///
  /// Match a result to an in-memory [PrescriptionRecord] by
  /// `card.uuid == record.remoteId`.
  Future<List<RemotePrescriptionCard>?> fetchForMember(
    String memberPhone,
  ) async {
    if (!NeonHttp.isConfigured || memberPhone.trim().isEmpty) {
      return null;
    }
    try {
      final rows = await NeonHttp.instance.query(
        r'''
          SELECT rx.code, rx.uuid, rx.status, rx.doctor,
                 pm.name, pm.pack,
                 pm.dose_morning, pm.dose_afternoon, pm.dose_night,
                 pm.total_units, pm.sort
          FROM app.prescription rx
          JOIN app.users u ON u.id = rx.member_id
          LEFT JOIN app.prescription_medicine pm ON pm.prescription_id = rx.id
          WHERE u.phone = $1 AND rx.deleted_at IS NULL
          ORDER BY rx.created_at DESC, pm.sort, pm.id
        ''',
        [memberPhone.trim()],
      );

      final byUuid = <String, RemotePrescriptionCard>{};
      final order = <String>[];
      for (final row in rows) {
        final uuid = (row['uuid'] ?? '').toString();
        if (uuid.isEmpty) {
          continue;
        }
        final card = byUuid.putIfAbsent(uuid, () {
          order.add(uuid);
          return RemotePrescriptionCard(
            code: (row['code'] ?? '').toString(),
            uuid: uuid,
            status: (row['status'] ?? '').toString().toUpperCase(),
            doctor: (row['doctor'] ?? '').toString(),
            medicines: [],
          );
        });
        final name = (row['name'] ?? '').toString().trim();
        if (name.isEmpty) {
          continue; // The LEFT JOIN row for a script with no lines yet.
        }
        card.medicines.add(
          RemotePrescriptionMedicine(
            name: name,
            pack: (row['pack'] ?? '').toString(),
            morning: _toInt(row['dose_morning']),
            afternoon: _toInt(row['dose_afternoon']),
            night: _toInt(row['dose_night']),
            totalUnits: _toInt(row['total_units']),
          ),
        );
      }
      return [for (final uuid in order) byUuid[uuid]!];
    } catch (error) {
      NeonHttp.log('PrescriptionRepository.fetchForMember failed', error: error);
      return null;
    }
  }

  /// Marks a prescription `ORDERED` once the customer places the fulfilment
  /// order. Found by [prescriptionUuid], else by the member's most recent
  /// non-ordered script. Best-effort.
  Future<void> markOrdered({
    required String memberPhone,
    String? prescriptionUuid,
  }) async {
    await _run<Object?>('markOrdered', () async {
      if (prescriptionUuid != null && prescriptionUuid.isNotEmpty) {
        await NeonHttp.instance.query(
          '''
            UPDATE app.prescription
               SET status = CASE WHEN status = 'AWAITING_REVIEW'
                                 THEN 'ORDERED'::app.prescription_status
                                 ELSE status END,
                   updated_at = now()
             WHERE uuid = \$1::uuid AND deleted_at IS NULL
          ''',
          [prescriptionUuid],
        );
        return null;
      }
      await NeonHttp.instance.query(
        '''
          UPDATE app.prescription rx
             SET status = 'ORDERED'::app.prescription_status, updated_at = now()
            FROM app.users u
           WHERE u.id = rx.member_id
             AND u.phone = \$1
             AND rx.status = 'AWAITING_REVIEW'
             AND rx.deleted_at IS NULL
        ''',
        [memberPhone],
      );
      return null;
    });
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// Inserts every medicine line for [prescriptionId] in one set-based
  /// statement.
  Future<void> _insertMedicines(
    int prescriptionId,
    List<PrescriptionMedicine> medicines,
  ) async {
    if (medicines.isEmpty) {
      return;
    }
    await NeonHttp.instance.query(
      '''
        INSERT INTO app.prescription_medicine
          (prescription_id, sort, name, pack,
           dose_morning, dose_afternoon, dose_night)
        SELECT \$1, m.sort, m.name, m.pack, m.morning, m.afternoon, m.night
        FROM unnest(
          \$2::int[], \$3::text[], \$4::text[],
          \$5::int[], \$6::int[], \$7::int[]
        ) AS m(sort, name, pack, morning, afternoon, night)
      ''',
      [
        prescriptionId,
        [for (var i = 0; i < medicines.length; i++) i],
        [for (final m in medicines) m.name],
        [for (final m in medicines) m.pack],
        [for (final m in medicines) m.intake.morning],
        [for (final m in medicines) m.intake.afternoon],
        [for (final m in medicines) m.intake.night],
      ],
    );
  }

  /// The `app.medicine_duration` enum label for [d], or null when no preset
  /// was chosen (a custom day count, or nothing yet).
  static String? _durationName(MedicineDuration? d) => switch (d) {
        MedicineDuration.oneWeek => 'ONE_WEEK',
        MedicineDuration.fifteenDays => 'FIFTEEN_DAYS',
        MedicineDuration.oneMonth => 'ONE_MONTH',
        MedicineDuration.twoMonths => 'TWO_MONTHS',
        MedicineDuration.threeMonths => 'THREE_MONTHS',
        null => null,
      };

  /// `2026-08-31` — an unambiguous value for a `date` column, or null.
  static String? _isoDate(DateTime? date) {
    if (date == null) {
      return null;
    }
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// The `id` of the first returned row as an int, or null when there is none.
  /// Neon's `/sql` endpoint returns every value as text.
  static int? _rowId(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return null;
    }
    final value = rows.first['id'] ?? rows.first.values.firstOrNull;
    if (value == null) {
      return null;
    }
    return value is int ? value : int.tryParse(value.toString());
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
      NeonHttp.log('PrescriptionRepository.$label failed', error: error);
      return null;
    }
  }
}
