import '../../module/checkout/fulfillment_type.dart';
import '../../module/prescription/medicine_duration.dart';
import 'backend_http.dart';

/// One prescription's pharmacist-built intake card, as read back from the
/// backend.
class RemotePrescriptionCard {
  final String code;
  final String? uuid;

  /// `AWAITING_REVIEW` / `READ` / `IN_CART` / `ORDERED` — the console's own
  /// status trail.
  final String status;
  final String doctor;
  final List<RemotePrescriptionMedicine> medicines;

  /// The rest of what a fresh install (or a reload on the web build) needs
  /// to rebuild a [PrescriptionRecord] wholesale from the backend, rather
  /// than only ever refreshing one that already exists locally — see
  /// `PrescriptionRepository.fetchForMember`'s own doc.
  final String? patientId;
  final String fileName;
  final MedicineDuration? duration;
  final int? customDays;
  final DateTime? recurringFrom;
  final DateTime? recurringUntil;

  RemotePrescriptionCard({
    required this.code,
    required this.uuid,
    required this.status,
    required this.doctor,
    required this.medicines,
    this.patientId,
    this.fileName = '',
    this.duration,
    this.customDays,
    this.recurringFrom,
    this.recurringUntil,
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
/// This originally covered only the upload/list/view slice — `markOrdered`
/// stayed on the old direct-Neon class until the order-checkout flow this
/// migration also covers, [submitForOrder] below, replaced it outright.
class PrescriptionRepository {
  PrescriptionRepository._();

  // Non-const, unlike before this feature — `_paymentMethodIdCache` below
  // needs a mutable instance field, the same reason `OrderRepository.instance`
  // switched from `const` too.
  static final PrescriptionRepository instance = PrescriptionRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// `code` (`'wallet'`/`'cash'`) → the backend's numeric `payment_method.id`
  /// — resolved once against the public catalogue and cached, mirroring
  /// `OrderRepository._paymentMethodIdFor`'s identical helper.
  Map<String, int>? _paymentMethodIdCache;

  Future<int?> _paymentMethodIdFor(String code) async {
    final cached = _paymentMethodIdCache;
    if (cached != null) {
      return cached[code];
    }
    try {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/catalogue/payment-methods',
        auth: false,
      ) as List<dynamic>;
      final map = <String, int>{};
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final rowCode = row['code']?.toString();
        final id = row['id'];
        if (rowCode != null && id != null) {
          map[rowCode] = (id as num).toInt();
        }
      }
      _paymentMethodIdCache = map;
      return map[code];
    } catch (error) {
      BackendHttp.log('PrescriptionRepository._paymentMethodIdFor failed', error: error);
      return null;
    }
  }

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
    List<String> images = const [],
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
          if (images.isNotEmpty) 'images': images,
          'fileName': fileName,
          'doctor': doctor,
          if (_durationName(duration) != null) 'duration': _durationName(duration),
          if (customDays != null) 'customDays': customDays,
          if (recurringFrom != null) 'recurringFrom': _isoDate(recurringFrom),
          if (recurringUntil != null) 'recurringUntil': _isoDate(recurringUntil),
        },
      ) as Map<String, dynamic>;
      final id = created['id']?.toString();
      BackendHttp.log(
        'PrescriptionRepository.insertUpload: saved $fileName '
        '(${images.length} image(s), $id)',
      );
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

  /// One prescription's own intake card — the same detail call
  /// [fetchForMember] makes per script, exposed standalone for a caller that
  /// already knows the id (Track Order's `PrescriptionUploadedCard`, keyed
  /// off the id `OrderRepository.fetchPrescriptions` already returned)
  /// rather than needing the whole account's list first.
  Future<RemotePrescriptionCard?> fetchOne(int id) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final detail = await BackendHttp.instance.request('GET', '/v1/member/prescriptions/$id')
          as Map<String, dynamic>;
      return _toCard(detail);
    } catch (error) {
      BackendHttp.log('PrescriptionRepository.fetchOne failed', error: error);
      return null;
    }
  }

  /// Submits one or more uploaded prescriptions for fulfilment —
  /// `POST /v1/member/prescription-orders`. An unpriced order shell the
  /// pharmacist prices at the counter, mirroring the old direct-Neon
  /// `OrderRepository.savePrescriptionOrder` + `markOrdered` exactly (see
  /// that endpoint's own doc): no pricing or payment logic here.
  ///
  /// [prescriptionIds] are the backend's numeric ids (the same value
  /// [insertUpload] returned and [fetchForMember]'s cards carry as `uuid` —
  /// an opaque pass-through identifier since the migration, not a real
  /// uuid). Returns the created order's id, or null when nothing was
  /// written.
  ///
  /// [fulfillmentType] and [paymentMethodCode] are migration-0031 additions:
  /// how the order reaches the member, and the member's stated payment
  /// preference — never charged here either way, a prescription is priced
  /// at the counter first.
  Future<int?> submitForOrder({
    required List<int> prescriptionIds,
    int? addressId,
    FulfillmentType fulfillmentType = FulfillmentType.homeDelivery,
    String? paymentMethodCode,
  }) async {
    if (!BackendHttp.isConfigured || prescriptionIds.isEmpty) {
      return null;
    }
    try {
      final paymentMethodId = paymentMethodCode == null
          ? null
          : await _paymentMethodIdFor(paymentMethodCode);
      final created = await BackendHttp.instance.request(
        'POST',
        '/v1/member/prescription-orders',
        body: {
          'prescriptionIds': prescriptionIds,
          if (addressId != null) 'addressId': addressId,
          if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
          'fulfillmentType': fulfillmentType == FulfillmentType.storePickup
              ? 'STORE_PICKUP'
              : 'HOME_DELIVERY',
        },
      ) as Map<String, dynamic>;
      return created['id'] as int?;
    } catch (error) {
      BackendHttp.log('PrescriptionRepository.submitForOrder failed', error: error);
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
      patientId: row['patientId']?.toString(),
      fileName: (row['fileName'] ?? '').toString(),
      duration: _durationFromName(row['duration']?.toString()),
      customDays: row['customDays'] == null ? null : _toInt(row['customDays']),
      recurringFrom: DateTime.tryParse((row['recurringFrom'] ?? '').toString()),
      recurringUntil: DateTime.tryParse((row['recurringUntil'] ?? '').toString()),
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

  static MedicineDuration? _durationFromName(String? name) => switch (name) {
    'ONE_WEEK' => MedicineDuration.oneWeek,
    'FIFTEEN_DAYS' => MedicineDuration.fifteenDays,
    'ONE_MONTH' => MedicineDuration.oneMonth,
    'TWO_MONTHS' => MedicineDuration.twoMonths,
    'THREE_MONTHS' => MedicineDuration.threeMonths,
    _ => null,
  };

  /// `2026-08-31` — an unambiguous value for the backend's date fields.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
