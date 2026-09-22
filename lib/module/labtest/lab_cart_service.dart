import 'package:flutter/foundation.dart';

import '../registration/registration_service.dart';
import 'lab_package.dart';
import 'lab_store.dart';

/// One package booked for a number of patients.
@immutable
class LabBooking {
  final LabPackage package;
  final int patients;

  const LabBooking({required this.package, required this.patients});

  /// The package price is per patient, so the line is priced per head.
  int get amount => package.priceValue * patients;

  int get mrpAmount => package.mrpValue * patients;

  LabBooking withPatients(int count) =>
      LabBooking(package: package, patients: count);
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
      _bookings.fold(0, (sum, booking) => sum + booking.patients);

  int get subtotal => _bookings.fold(0, (sum, booking) => sum + booking.amount);

  int get mrpTotal =>
      _bookings.fold(0, (sum, booking) => sum + booking.mrpAmount);

  int get savings => mrpTotal - subtotal;

  /// Home collection is included; stated as a getter so a fee can be
  /// introduced in one place.
  int get collectionFee => 0;

  int get payable => subtotal + collectionFee;

  /// How many patients this package is currently booked for, or null when it
  /// is not in the basket. The detail screen opens its sheet on this.
  int? patientsFor(LabPackage package) {
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
  /// booking the same panel twice is a correction to the patient count, not a
  /// second visit.
  void book(LabPackage package, {required int patients}) {
    final count = patients.clamp(1, maxPatients);
    final index = _bookings.indexWhere(
      (booking) => booking.package.name == package.name,
    );

    if (index == -1) {
      _bookings.add(LabBooking(package: package, patients: count));
    } else {
      _bookings[index] = _bookings[index].withPatients(count);
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

  @visibleForTesting
  void reset() {
    _bookings.clear();
    _chosenStore = null;
    notifyListeners();
  }
}
