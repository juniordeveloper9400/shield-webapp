import 'package:flutter/foundation.dart';

import '../location/address_book.dart';
import '../patients/patient_book.dart';
import '../registration/registration_service.dart';
import 'lab_fulfillment_type.dart';
import 'lab_package.dart';
import 'lab_store.dart';

export 'lab_fulfillment_type.dart' show LabFulfillmentType;

/// One package booked for a named list of patients — each may carry their
/// own collection address (see [LabCartService.addressFor]); one with none
/// of its own falls back to the basket's shared delivery address.
@immutable
class LabBooking {
  final LabPackage package;
  final List<Patient> patients;

  const LabBooking({required this.package, required this.patients});

  /// The package price is per patient, so the line is priced per head.
  int get amount => package.priceValue * patients.length;

  int get mrpAmount => package.mrpValue * patients.length;

  LabBooking withPatients(List<Patient> next) =>
      LabBooking(package: package, patients: next);
}

/// The lab basket.
///
/// Deliberately separate from `CartService`: a diagnostic booking is a
/// scheduled home visit priced per patient, not a boxed product with a
/// quantity, and mixing the two would mean one delivery fee and one checkout
/// over two things that are settled in completely different ways.
///
/// In memory only; a backend would replace this class wholesale.
class LabCartService extends ChangeNotifier {
  LabCartService._();

  static final LabCartService instance = LabCartService._();

  /// The most patients one booking may cover, matching the sheet's options.
  static const int maxPatients = 5;

  final List<LabBooking> _bookings = [];

  /// Each patient's own collection address, by [Patient.id] — set from the
  /// checkout screen's own per-patient "Change" (see [setAddressFor]).
  /// Absent for a patient who has not been given one of their own yet; that
  /// patient's visit then goes to the basket's shared delivery address
  /// ([AddressBook.instance.deliverTo]) instead, the original behaviour.
  final Map<String, Address> _addressByPatientId = {};

  /// This patient's own address, or null when they have none of their own
  /// (the basket's shared address applies to them instead).
  Address? addressFor(Patient patient) => _addressByPatientId[patient.id];

  /// Records (or clears, passing null) [patient]'s own collection address —
  /// does not touch any other patient's, or the basket's shared one.
  void setAddressFor(Patient patient, Address? address) {
    if (address == null) {
      _addressByPatientId.remove(patient.id);
    } else {
      _addressByPatientId[patient.id] = address;
    }
    notifyListeners();
  }

  /// The member's own branch pick for this basket — set by [chooseStore]
  /// (from [LabStorePickerSheet]) or by [defaultStoreIfNeeded] once the live
  /// branch list has loaded. Unlike root's `LabCartService`, this is kept as
  /// the fetched [LabStore] itself rather than re-resolved from an id: this
  /// app has no live-synced store directory to resolve it against (see
  /// `lab_store.dart`'s own doc), only the one-off read the picker made.
  LabStore? _chosenStore;

  LabStore? get store => _chosenStore;

  /// Records the member's own branch pick from the checkout's "Branch" row.
  void chooseStore(LabStore store) {
    _chosenStore = store;
    notifyListeners();
  }

  /// How this basket's samples reach the lab — home collection by default,
  /// matching the booking flow's original (and still most common) behaviour.
  LabFulfillmentType _fulfillmentType = LabFulfillmentType.homeCollection;

  LabFulfillmentType get fulfillmentType => _fulfillmentType;

  /// Records the member's own pick from the checkout's service-type row. A
  /// switch to store visit does not clear any address already chosen — it's
  /// simply not required any more, and switching back to home collection
  /// should not make the member pick an address again if they already had.
  void chooseFulfillmentType(LabFulfillmentType type) {
    if (_fulfillmentType == type) return;
    _fulfillmentType = type;
    notifyListeners();
  }

  /// The member's preferred date for collection/visit, from the checkout's
  /// "Preferred date" row — optional. The lab can still set or change it
  /// from the admin console's own Schedule section regardless.
  DateTime? _scheduledFor;

  DateTime? get scheduledFor => _scheduledFor;

  /// Records (or clears, passing null) the member's own pick from the
  /// checkout's "Preferred date" row.
  void chooseScheduledFor(DateTime? date) {
    _scheduledFor = date;
    notifyListeners();
  }

  /// Defaults the branch to the member's registered home branch, matched by
  /// code against [eligible] — the live, lab-collection-eligible list
  /// [LabCartScreen]'s branch row just fetched. A no-op once something has
  /// already been chosen, or when the home branch is not in [eligible]
  /// (switched off for lab, or not recognised at all).
  void defaultStoreIfNeeded(List<LabStore> eligible) {
    if (_chosenStore != null) {
      return;
    }
    final homeCode = RegistrationService.instance.profile?.storeId;
    if (homeCode == null) {
      return;
    }
    for (final store in eligible) {
      if (store.code == homeCode) {
        _chosenStore = store;
        notifyListeners();
        return;
      }
    }
  }

  List<LabBooking> get bookings => List.unmodifiable(_bookings);

  bool get isEmpty => _bookings.isEmpty;

  /// Number of packages booked — what the badge shows.
  ///
  /// Packages, not patients: two people booked onto one panel is still one
  /// thing in the basket, and one line on the screen.
  int get bookingCount => _bookings.length;

  /// Every head across every booking, which is what the collection visit has
  /// to plan for.
  int get patientCount =>
      _bookings.fold(0, (sum, booking) => sum + booking.patients.length);

  int get subtotal => _bookings.fold(0, (sum, booking) => sum + booking.amount);

  int get mrpTotal =>
      _bookings.fold(0, (sum, booking) => sum + booking.mrpAmount);

  int get savings => mrpTotal - subtotal;

  /// Home collection is included; stated as a getter so a fee can be
  /// introduced in one place.
  int get collectionFee => 0;

  int get payable => subtotal + collectionFee;

  /// The patients this package is currently booked for, or null when it is
  /// not in the basket. The detail screen opens its picker sheet on this.
  List<Patient>? patientsFor(LabPackage package) {
    for (final booking in _bookings) {
      if (booking.package.name == package.name) {
        return booking.patients;
      }
    }
    return null;
  }

  /// Books [package] for [patients].
  ///
  /// Replaces rather than adds when the package is already in the basket:
  /// booking the same panel twice is a correction to who it covers, not a
  /// second visit.
  void book(LabPackage package, {required List<Patient> patients}) {
    final seen = <String>{};
    final chosen = patients
        .where((p) => seen.add(p.id))
        .take(maxPatients)
        .toList();
    final index = _bookings.indexWhere(
      (booking) => booking.package.name == package.name,
    );

    if (index == -1) {
      _bookings.add(LabBooking(package: package, patients: chosen));
    } else {
      _bookings[index] = _bookings[index].withPatients(chosen);
    }
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _bookings.length) {
      return;
    }
    _bookings.removeAt(index);
    notifyListeners();
  }

  void remove(LabPackage package) {
    _bookings.removeWhere((booking) => booking.package.name == package.name);
    notifyListeners();
  }

  /// Empties the basket once its bookings have actually been placed — the
  /// same moment the commerce cart empties itself after "Place order".
  void clear() {
    _bookings.clear();
    _addressByPatientId.clear();
    _chosenStore = null;
    _fulfillmentType = LabFulfillmentType.homeCollection;
    _scheduledFor = null;
    notifyListeners();
  }

  @visibleForTesting
  void reset() => clear();
}
