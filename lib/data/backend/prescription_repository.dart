import '../../module/prescription/medicine_duration.dart';
import 'backend_http.dart';

/// One prescription's pharmacist-built intake card, as read back from the
/// backend.
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

/// Uploads and reads back prescriptions through `backend/api`'s
/// `/v1/member/prescriptions` routes — see `prescription.service.ts`.
///
/// Best-effort: an unconfigured backend (tests) or the network down makes
/// the call no-op and return null rather than throw. Uploading a
/// prescription must never fail because the backend is unreachable —
/// [PrescriptionBook] stays the source of truth for the running app, and
/// this row is the durable copy.
///
/// This covers only the upload/list/view slice of what the old direct-Neon
/// `PrescriptionRepository` did — `markOrdered` (tightly coupled to the
/// deferred order-checkout flow) stays on the old class in
/// `lib/data/neon/prescription_repository.dart` for now.
class PrescriptionRepository {
  const PrescriptionRepository._();

  static const PrescriptionRepository instance = PrescriptionRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// Records a freshly uploaded prescription against an already-known
  /// [patientId] (resolve/create the patient via `PatientRepository`
  /// *first* — the backend has no inline "create the patient as part of
  /// this upload" path, unlike the old direct-Neon version).
  ///
  /// Medicine lines are not accepted here: the backend only ever lets
  /// *staff* add them (`POST /v1/staff/prescriptions/:id/medicines`) — a
  /// member-submitted line at upload time was already "usually none" in the
  /// old flow (the counter fills them in), so nothing is lost in practice.
  ///
  /// Returns the created prescription's id (as a string, standing in for
  /// the old row's uuid — an opaque pass-through identifier to every call
  /// site either way), or null when nothing was written.
  Future<String?> insertUpload({
    required int patientId,
    required String fileName,
    String? image,
    String doctor = '',
    MedicineDuration? duration,
    int? customDays,
    DateTime? recurringFrom,
    DateTime? recurringUntil,
  }) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final created = await BackendHttp.instance.request(
        'POST',
        '/v1/member/prescriptions',
        body: {
          'patientId': patientId,
          if (image != null && image.isNotEmpty) 'image': image,
          'fileName': fileName,
          'doctor': doctor,
          if (_durationName(duration) != null) 'duration': _durationName(duration),
          if (customDays != null) 'customDays': customDays,
          if (recurringFrom != null) 'recurringFrom': _isoDate(recurringFrom),
          if (recurringUntil != null) 'recurringUntil': _isoDate(recurringUntil),
        },
      ) as Map<String, dynamic>;
      final id = created['id']?.toString();
      BackendHttp.log('PrescriptionRepository.insertUpload: saved $fileName ($id)');
      return id;
    } catch (error) {
      BackendHttp.log('PrescriptionRepository.insertUpload failed', error: error);
      return null;
    }
  }

  /// The pharmacist-built intake cards for every prescription on the
  /// account: one list call plus one detail call per prescription (the list
  /// response carries no medicine lines) — a member's own prescriptions are
  /// few, so the N+1 is not a real cost.
  ///
  /// Returns null when the backend is off or unreachable (so "not loaded"
  /// reads differently from "nothing sent yet").
  ///
  /// Match a result to an in-memory `PrescriptionRecord` by
  /// `card.uuid == record.remoteId` (an id string, not a real uuid, since
  /// the migration — see this class's own doc on [insertUpload]).
  Future<List<RemotePrescriptionCard>?> fetchForMember(String memberPhone) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final list = await BackendHttp.instance.request('GET', '/v1/member/prescriptions')
          as List<dynamic>;
      final cards = <RemotePrescriptionCard>[];
      for (final row in list.cast<Map<String, dynamic>>()) {
        final id = row['id'];
        if (id == null) {
          continue;
        }
        final detail = await BackendHttp.instance.request('GET', '/v1/member/prescriptions/$id')
            as Map<String, dynamic>;
        cards.add(_toCard(detail));
      }
      return cards;
    } catch (error) {
      BackendHttp.log('PrescriptionRepository.fetchForMember failed', error: error);
      return null;
    }
  }

  static RemotePrescriptionCard _toCard(Map<String, dynamic> row) {
    final medicines = (row['medicines'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((m) => (m['name'] ?? '').toString().trim().isNotEmpty)
        .map(
          (m) => RemotePrescriptionMedicine(
            name: (m['name'] ?? '').toString().trim(),
            pack: (m['pack'] ?? '').toString(),
            morning: _toInt(m['doseMorning']),
            afternoon: _toInt(m['doseAfternoon']),
            night: _toInt(m['doseNight']),
            totalUnits: _toInt(m['totalUnits']),
          ),
        )
        .toList();
    return RemotePrescriptionCard(
      code: (row['code'] ?? '').toString(),
      uuid: row['id']?.toString(),
      status: (row['status'] ?? '').toString().toUpperCase(),
      doctor: (row['doctor'] ?? '').toString(),
      medicines: medicines,
    );
  }

  static int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String? _durationName(MedicineDuration? d) => switch (d) {
    MedicineDuration.oneWeek => 'ONE_WEEK',
    MedicineDuration.fifteenDays => 'FIFTEEN_DAYS',
    MedicineDuration.oneMonth => 'ONE_MONTH',
    MedicineDuration.twoMonths => 'TWO_MONTHS',
    MedicineDuration.threeMonths => 'THREE_MONTHS',
    null => null,
  };

  /// `2026-08-31` — an unambiguous value for the backend's date fields.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
