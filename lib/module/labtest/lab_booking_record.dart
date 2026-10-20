/// Where a lab order is, as the member reads it: Requested → Verified →
/// Billed → Completed (or Cancelled). `backend/api` works the stage out from
/// what the admin has actually done — verified the bill, converted it to a
/// bill, collected the payment — and sends it as `stage`.
enum LabStage {
  requested('Requested'),
  verified('Verified'),
  billed('Billed'),
  completed('Completed'),
  cancelled('Cancelled');

  const LabStage(this.label);

  final String label;

  /// Reads the backend's `stage`, or — from a backend that does not send one
  /// yet — the older `app.lab_booking_status`. An unknown value reads as
  /// [requested] rather than throwing on a screen that only wants to list
  /// orders.
  static LabStage parse(Object? value) {
    switch ((value ?? '').toString().trim().toUpperCase()) {
      case 'VERIFIED':
      case 'CONFIRMED':
      case 'SAMPLE_COLLECTED':
        return LabStage.verified;
      case 'BILLED':
        return LabStage.billed;
      case 'COMPLETED':
      case 'REPORT_READY':
        return LabStage.completed;
      case 'CANCELLED':
        return LabStage.cancelled;
      default:
        return LabStage.requested;
    }
  }
}

/// One patient named on a lab order.
class LabPatientLine {
  final String name;
  final int? age;

  const LabPatientLine({required this.name, this.age});

  String get label => age == null ? name : '$name · $age yrs';
}

/// One of the member's lab bookings, as the My Lab Bookings screen shows it.
class LabBookingRecord {
  final int id;
  final String packageName;
  final int patients;
  final double total;
  final LabStage stage;

  /// When the lab has scheduled the sample collection, if it has.
  final DateTime? scheduledFor;

  /// A line from the lab to the member ("Please come fasting"); '' if none.
  final String note;

  /// How many report pages the lab has attached. The pages themselves are
  /// fetched only when the member opens the report.
  final int reportPages;
  final DateTime? createdAt;
  final double fuelCharge;
  final double techFee;
  final bool isVerified;

  /// Price per patient, before any visit charges — what the order summary
  /// multiplies by [patients].
  final double unitPrice;

  /// True for a home collection, false when the member visits the branch.
  final bool homeCollection;

  /// The branch the booking is routed to; '' when none is recorded.
  final String storeName;

  /// Who the lab assigned to collect the sample; '' until it assigns one.
  final String collectorName;

  /// Where the sample is collected — an admin's correction wins over the
  /// member's saved address; '' for a store visit or when none is recorded.
  final String address;

  /// Who the booking is for, as named on the order.
  final List<LabPatientLine> patientList;

  const LabBookingRecord({
    required this.id,
    required this.packageName,
    required this.patients,
    required this.total,
    required this.stage,
    this.scheduledFor,
    this.note = '',
    this.reportPages = 0,
    this.createdAt,
    this.fuelCharge = 0,
    this.techFee = 0,
    this.isVerified = false,
    this.unitPrice = 0,
    this.homeCollection = true,
    this.storeName = '',
    this.collectorName = '',
    this.address = '',
    this.patientList = const [],
  });

  /// The label the console shows for the same booking — `LB-0007`.
  String get code => 'LB-${id.toString().padLeft(4, '0')}';

  /// The report can be opened: the lab marked it ready and attached pages.
  bool get reportAvailable => stage == LabStage.completed && reportPages > 0;

  /// Reads one booking from `backend/api`'s `GET /v1/member/lab-bookings`.
  factory LabBookingRecord.fromJson(Map<String, dynamic> json) {
    final rawNote = _text(json['note']);
    final billMatch = RegExp(r'\[BILL_VERIFIED:\s*fuel=(\d+(?:\.\d+)?),\s*tech=(\d+(?:\.\d+)?)\]').firstMatch(rawNote);
    final verified = json['isVerified'] == true || billMatch != null;
    final fuel = json['fuelCharge'] != null
        ? _num(json['fuelCharge'])
        : (billMatch != null ? double.tryParse(billMatch.group(1)!) ?? 0.0 : 0.0);
    final tech = json['techFee'] != null
        ? _num(json['techFee'])
        : (billMatch != null ? double.tryParse(billMatch.group(2)!) ?? 0.0 : 0.0);
    final cleanNote = billMatch != null
        ? rawNote.replaceAll(RegExp(r'\[BILL_VERIFIED:\s*fuel=\d+(?:\.\d+)?,\s*tech=\d+(?:\.\d+)?\]\s*'), '').trim()
        : rawNote;

    return LabBookingRecord(
      id: _int(json['id']),
      packageName: _text(json['packageName'], fallback: 'Lab test'),
      patients: _int(json['patientsCount'], fallback: 1),
      total: _num(json['totalPrice']),
      stage: LabStage.parse(json['stage'] ?? json['status']),
      scheduledFor: _date(json['scheduledFor']),
      note: cleanNote,
      reportPages: _int(json['reportPages']),
      createdAt: _date(json['createdAt']),
      fuelCharge: fuel,
      techFee: tech,
      isVerified: verified,
      unitPrice: _num(json['unitPrice']),
      homeCollection:
          _text(json['fulfillmentType']).toUpperCase() != 'STORE_VISIT',
      storeName: _text(json['storeName']),
      collectorName: _text(json['collectorName']),
      address: _text(json['address']),
      patientList: [
        for (final row in (json['patientList'] as List<dynamic>? ?? const []))
          if (row is Map<String, dynamic>)
            LabPatientLine(
              name: _text(row['name'], fallback: 'Patient'),
              age: row['age'] is num ? (row['age'] as num).toInt() : null,
            ),
      ],
    );
  }

  static int _int(Object? value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  static double _num(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static String _text(Object? value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static DateTime? _date(Object? value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
  }
}

/// What the lab-booking screens need from the outside world, so a test can
/// stand in for the database or backend.
class LabBookingSource {
  /// The member's bookings, newest first; null when they could not be loaded.
  final Future<List<LabBookingRecord>?> Function() loadBookings;

  /// The pages of one booking's report (`data:` URIs), in order; null when
  /// they could not be loaded.
  final Future<List<String>?> Function(int bookingId) loadReportPages;

  const LabBookingSource({
    required this.loadBookings,
    required this.loadReportPages,
  });
}
