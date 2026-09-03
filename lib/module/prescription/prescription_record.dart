import 'package:flutter/foundation.dart';

import '../../dates.dart';
import '../patients/patient_book.dart';
import 'medicine_duration.dart';

/// How much is taken at each of the three times of day a prescription is
/// written for, in the order they are read out: morning, afternoon, night.
///
/// Kept as three numbers rather than as the string a pharmacist writes, so the
/// total to dispense can be worked out from it. `101` is one in the morning
/// and one at night; `110` is morning and afternoon; `001` is night only.
@immutable
class IntakePattern {
  final int morning;
  final int afternoon;
  final int night;

  const IntakePattern({this.morning = 0, this.afternoon = 0, this.night = 0});

  /// Nothing entered yet — not "none prescribed".
  static const IntakePattern none = IntakePattern();

  /// Reads `101`, or `1-0-1`, back into a pattern.
  ///
  /// Returns null for anything that is not three digits rather than guessing:
  /// a half-typed `10` means the row is not ready, not that the night dose is
  /// zero.
  static IntakePattern? tryParse(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 3) {
      return null;
    }
    return IntakePattern(
      morning: int.parse(digits[0]),
      afternoon: int.parse(digits[1]),
      night: int.parse(digits[2]),
    );
  }

  /// `101` — the form it is written in on the prescription.
  String get code => '$morning$afternoon$night';

  int get perDay => morning + afternoon + night;

  /// Three zeroes: a valid code, but not a dose anyone can dispense against.
  bool get isEmpty => perDay == 0;

  /// The code spelled out — "Morning & night" — so a member who has not met
  /// the notation can still read the row.
  ///
  /// Takes the three slot names from the screen's copy rather than holding
  /// English of its own, because the card is shown in both languages.
  String labelWith(List<String> slots, String emptyLabel) {
    assert(slots.length == 3);
    final counts = [morning, afternoon, night];
    final parts = <String>[];
    for (var index = 0; index < 3; index++) {
      final count = counts[index];
      if (count == 0) {
        continue;
      }
      parts.add(count > 1 ? '${slots[index]} ×$count' : slots[index]);
    }
    if (parts.isEmpty) {
      return emptyLabel;
    }
    if (parts.length == 1) {
      return parts.single;
    }
    // Only the first slot keeps its capital: the label is one phrase, not a
    // list of three headings. Malayalam has no case, so this is a no-op there.
    final tail = parts.skip(1).map((part) => part.toLowerCase()).toList();
    if (tail.length == 1) {
      return '${parts.first} & ${tail.single}';
    }
    return '${parts.first}, ${tail.take(tail.length - 1).join(', ')} '
        '& ${tail.last}';
  }

  /// Units to dispense over [days].
  int totalFor(int days) => perDay * days;

  @override
  bool operator ==(Object other) =>
      other is IntakePattern &&
      other.morning == morning &&
      other.afternoon == afternoon &&
      other.night == night;

  @override
  int get hashCode => Object.hash(morning, afternoon, night);
}

/// One medicine line, as the pharmacy counter read it off the prescription.
///
/// Immutable, and deliberately so: these lines are not the member's to write.
/// A pharmacist reads the prescription, keys in what it says, and this is the
/// result being shown back — a member who could retype the dose here could
/// order a dose the prescription does not authorise.
@immutable
class PrescriptionMedicine {
  final String name;

  /// How it is sold — "Strip of 15 tablets". Carried through to the cart line
  /// so the counted units mean something there too.
  final String pack;

  final IntakePattern intake;

  /// Units the pharmacist wrote for this line in the console. Null on a line
  /// that pre-dates the intake card (the old auto-read flow), where the total
  /// is worked out from [intake] over the prescription's day count instead.
  final int? totalUnits;

  const PrescriptionMedicine({
    required this.name,
    this.pack = '',
    this.intake = IntakePattern.none,
    this.totalUnits,
  });

  /// Enough to dispense against: something to look up, and a dose above zero.
  bool get isComplete => name.trim().isNotEmpty && !intake.isEmpty;

  /// The number of units on this line: the pharmacist's figure when they gave
  /// one, otherwise the intake pattern spread over [days].
  int unitsFor(int days) => totalUnits ?? intake.totalFor(days);
}

/// When a repeat prescription starts, and when it stops.
///
/// [until] being null is the "never expires" tick: a long-term prescription
/// for a chronic condition has a start date and no end, and storing that as
/// an absent date rather than as a far-future one keeps the two apart.
@immutable
class RecurringSchedule {
  final DateTime from;
  final DateTime? until;

  const RecurringSchedule({required this.from, this.until});

  bool get neverExpires => until == null;

  String get fromLabel => formatDate(from);

  String get untilLabel => until == null ? '' : formatDate(until!);

  /// Whether [day] falls inside the run. An open-ended schedule is live from
  /// its start date onwards.
  bool covers(DateTime day) {
    if (day.isBefore(DateTime(from.year, from.month, from.day))) {
      return false;
    }
    final end = until;
    if (end == null) {
      return true;
    }
    return !day.isAfter(DateTime(end.year, end.month, end.day, 23, 59, 59));
  }
}

/// A prescription that has been uploaded, and what the pharmacy read on it.
///
/// The member owns the top half — who it is for, how long a supply, whether
/// it repeats. The pharmacy owns the bottom half: the prescriber and the
/// medicines, written by [PrescriptionBook.fillFromPharmacy] when the counter
/// has read the file, and only shown here.
class PrescriptionRecord {
  final String id;
  final Patient patient;

  /// Read off the prescription at the counter. Empty until it has been, which
  /// is what the card draws its waiting state from.
  String doctor;

  /// The name of the uploaded file, kept so the card can say which image it
  /// is showing without holding the bytes.
  final String fileName;

  final MedicineDuration? duration;
  final int? customDays;
  final RecurringSchedule? recurring;

  /// What the pharmacy keyed in. Empty until they have.
  List<PrescriptionMedicine> medicines;

  /// Set once its medicines have been sent to the cart, so the card can say
  /// so instead of offering to send them twice.
  bool inCart;

  /// Set once the customer has placed the fulfilment order for this script.
  /// Until the pharmacist sends the intake card the record then shows a plain
  /// "we're on it" state; once [medicines] arrive the card expands.
  bool ordered;

  /// The `uuid` of this prescription's row in `app.prescription` on the
  /// backend, once one has been written. Null when the record has only ever
  /// lived in memory — a build with no `DATABASE_URL`, or a save made while
  /// the database was unreachable. Carried so the pharmacy read and, later,
  /// the order update the same row instead of inserting another.
  String? remoteId;

  PrescriptionRecord({
    required this.id,
    required this.patient,
    required this.fileName,
    this.doctor = '',
    this.duration,
    this.customDays,
    this.recurring,
    List<PrescriptionMedicine>? medicines,
    this.inCart = false,
    this.ordered = false,
    this.remoteId,
  }) : medicines = medicines ?? <PrescriptionMedicine>[];

  /// "RX-0004" — the prescription's number, as it is quoted at the counter
  /// and printed in the basket.
  ///
  /// Built from [id] rather than stored beside it, so the two can never name
  /// different prescriptions. The id is the internal handle ("rx4"); this is
  /// the same thing in the form a member can read out over a phone, padded so
  /// a list of them lines up.
  String get number {
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    return 'RX-${digits.padLeft(4, '0')}';
  }

  bool get isRecurring => recurring != null;

  /// Uploaded, but the fulfilment order has not been placed yet.
  bool get isAwaitingOrder => !ordered;

  /// Order placed, but the pharmacist has not sent the intake card back — the
  /// card shows a plain "we have your prescription" state.
  bool get awaitingPharmacist => ordered && medicines.isEmpty;

  /// The pharmacist has sent the intake card — the medicines can be shown.
  bool get hasIntakeCard => medicines.isNotEmpty;

  /// Uploaded, but not yet read at the counter. Kept for callers that still
  /// phrase it this way; true whenever no intake lines are on the record.
  bool get isAwaitingReview => medicines.isEmpty;

  /// The run the totals are worked out over. A manual number of days wins
  /// over a preset, because it is what the member typed last.
  int get days => customDays ?? duration?.days ?? 0;

  String get supplyLabel {
    if (customDays != null && customDays! > 0) {
      return "$customDays days · $customDays days' supply";
    }
    return duration?.supplyLabel ?? '';
  }

  /// Lines that can be dispensed. A half-filled row is left out rather than
  /// sent to the cart as a blank.
  List<PrescriptionMedicine> get dispensable =>
      medicines.where((medicine) => medicine.isComplete).toList();

  bool get canOrder => dispensable.isNotEmpty && days > 0;

  /// Total units across every complete line — the pharmacist's figures where
  /// they gave them, otherwise the intake pattern over [days].
  int get totalUnits => dispensable.fold(
    0,
    (sum, medicine) => sum + medicine.unitsFor(days),
  );
}

/// The prescriptions on the account.
///
/// In memory only, and shared the way [PatientBook] is: the upload screen
/// shows the list, and anything else that comes to need it — reorder, the
/// approvals screen — reads the same records rather than a second copy.
class PrescriptionBook extends ChangeNotifier {
  PrescriptionBook._();

  static final PrescriptionBook instance = PrescriptionBook._();

  final List<PrescriptionRecord> _records = [];

  int _nextId = 1;

  List<PrescriptionRecord> get records => List.unmodifiable(_records);

  bool get isEmpty => _records.isEmpty;

  int get length => _records.length;

  /// Builds the record, files it, and hands it back with its id.
  PrescriptionRecord add({
    required Patient patient,
    required String fileName,
    String doctor = '',
    MedicineDuration? duration,
    int? customDays,
    RecurringSchedule? recurring,
    List<PrescriptionMedicine>? medicines,
  }) {
    final record = PrescriptionRecord(
      id: 'rx${_nextId++}',
      patient: patient,
      fileName: fileName,
      doctor: doctor,
      duration: duration,
      customDays: customDays,
      recurring: recurring,
      medicines: medicines,
    );
    _records.add(record);
    notifyListeners();
    return record;
  }

  /// Puts a record back where it was, which is what Undo on the delete
  /// snackbar needs: restoring it to the end would reshuffle the list.
  void insert(int index, PrescriptionRecord record) {
    _records.insert(index.clamp(0, _records.length), record);
    notifyListeners();
  }

  int indexOf(String id) => _records.indexWhere((record) => record.id == id);

  /// Pins the backend row's [remoteId] onto the in-memory record once the
  /// upload write returns. A no-op when the id is unknown (the record was
  /// deleted again before the round trip finished).
  void attachRemoteId(String id, String remoteId) {
    final index = indexOf(id);
    if (index == -1) {
      return;
    }
    _records[index].remoteId = remoteId;
    notifyListeners();
  }

  void remove(String id) {
    _records.removeWhere((record) => record.id == id);
    notifyListeners();
  }

  /// Writes back what the pharmacy counter read off the prescription.
  ///
  /// The one way medicines get onto a record. Keeping it here rather than
  /// letting screens assign to `record.medicines` means the list always
  /// arrives whole, from one place, and every listener hears about it — which
  /// is exactly the shape a backend push would take.
  void fillFromPharmacy(
    String id, {
    required List<PrescriptionMedicine> medicines,
    String doctor = '',
  }) {
    final index = indexOf(id);
    if (index == -1) {
      return;
    }
    final record = _records[index];
    record.medicines = List.unmodifiable(medicines);
    if (doctor.isNotEmpty) {
      record.doctor = doctor;
    }
    notifyListeners();
  }

  /// Marks the record's fulfilment order as placed.
  void markOrdered(String id) {
    final index = indexOf(id);
    if (index == -1) {
      return;
    }
    _records[index].ordered = true;
    notifyListeners();
  }

  /// Folds in the pharmacist's intake card once it has been read back from the
  /// backend: the medicine lines and, if it carries one, the prescriber.
  /// [ordered] is set true when the backend row shows the order was placed on
  /// another device.
  void applyIntakeCard(
    String id, {
    required List<PrescriptionMedicine> medicines,
    String doctor = '',
    bool ordered = false,
  }) {
    final index = indexOf(id);
    if (index == -1) {
      return;
    }
    final record = _records[index];
    var changed = false;
    if (!_sameMedicines(record.medicines, medicines)) {
      record.medicines = List.unmodifiable(medicines);
      changed = true;
    }
    if (doctor.isNotEmpty && record.doctor != doctor) {
      record.doctor = doctor;
      changed = true;
    }
    if (ordered && !record.ordered) {
      record.ordered = true;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  static bool _sameMedicines(
    List<PrescriptionMedicine> a,
    List<PrescriptionMedicine> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name ||
          a[i].intake != b[i].intake ||
          a[i].totalUnits != b[i].totalUnits) {
        return false;
      }
    }
    return true;
  }

  /// Announces a change made to a record in place, such as its lines reaching
  /// the cart, since the records themselves are mutable.
  void touch() => notifyListeners();

  @visibleForTesting
  void reset() {
    _records.clear();
    _nextId = 1;
    notifyListeners();
  }
}
