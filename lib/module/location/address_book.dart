import 'package:flutter/foundation.dart';

import '../../data/backend/address_repository.dart';

/// What a saved address is used for.
enum AddressLabel {
  home('Home'),
  work('Work'),
  other('Other');

  final String label;

  const AddressLabel(this.label);
}

/// A delivery address.
@immutable
class Address {
  final String pincode;
  final String house;
  final String area;
  final String landmark;
  final String firstName;
  final String lastName;
  final String phone;
  final AddressLabel label;

  /// The patient this address was captured for, when it came off the
  /// patient form rather than the standalone address form — null for an
  /// address added any other way. Lets [AddressBook.upsertForPatient] find
  /// and replace the one address that belongs to a given patient instead of
  /// piling up a fresh entry every time their details are edited.
  final String? patientId;

  const Address({
    required this.pincode,
    required this.house,
    required this.area,
    required this.firstName,
    required this.phone,
    required this.label,
    this.landmark = '',
    this.lastName = '',
    this.patientId,
  });

  String get receiver => lastName.isEmpty ? firstName : '$firstName $lastName';

  /// Single-line rendering for lists.
  String get summary {
    final parts = [house, area, if (landmark.isNotEmpty) landmark, pincode];
    return parts.where((part) => part.isNotEmpty).join(', ');
  }
}

/// Saved delivery addresses, and which one is being delivered to.
///
/// Also the single owner of the current delivery location, so the two ways of
/// setting it — a bare pincode from the location sheet, or a full address
/// saved in the form — end up in the same place and every surface showing the
/// location updates from one notification.
///
/// In memory only; a backend would replace this class wholesale.
class AddressBook extends ChangeNotifier {
  AddressBook._();

  static final AddressBook instance = AddressBook._();

  /// Where the app delivers until told otherwise.
  static const String defaultPincode = '400079';

  /// Pincodes the app can name a city for. Anything else is shown as-is.
  static const Map<String, String> knownCities = {
    '400079': 'Mumbai',
    '110001': 'Delhi',
    '560001': 'Bengaluru',
    '600001': 'Chennai',
    '682001': 'Kochi',
    '700001': 'Kolkata',
  };

  /// "400079, Mumbai" when the city is known, otherwise just the pincode.
  static String describePincode(String pincode) {
    final city = knownCities[pincode];
    return city == null ? pincode : '$pincode, $city';
  }

  final List<Address> _addresses = [];

  String _pincode = defaultPincode;
  Address? _deliverTo;

  List<Address> get addresses => List.unmodifiable(_addresses);

  bool get isEmpty => _addresses.isEmpty;

  /// The address captured for [patientId] on their own patient form, if any.
  Address? forPatient(String patientId) {
    for (final address in _addresses) {
      if (address.patientId == patientId) {
        return address;
      }
    }
    return null;
  }

  /// The saved address being delivered to, or null when the location is just
  /// a pincode.
  Address? get deliverTo => _deliverTo;

  String get pincode => _deliverTo?.pincode ?? _pincode;

  /// What the chrome shows: the pincode and the place it belongs to.
  ///
  /// A saved address names its own locality, which beats the city lookup —
  /// "400079, Ghatkopar East" is more use than "400079, Mumbai".
  String get locationLabel {
    final address = _deliverTo;
    if (address != null && address.area.isNotEmpty) {
      return '${address.pincode}, ${address.area}';
    }
    return describePincode(pincode);
  }

  /// Saves an address and starts delivering to it. Saving an address is a
  /// statement about where you want things sent, so it takes effect at once.
  void add(Address address) {
    _addresses.add(address);
    _deliverTo = address;
    notifyListeners();
  }

  /// Merges the member's real, backend-saved addresses in — see
  /// `AddressRepository.fetchAll`'s doc for why this has to run at all: this
  /// class was, until now, "in memory only," so an address saved in an
  /// earlier session (or, on the web build, before the last page reload)
  /// read as never having been saved at all. Best-effort and additive: an
  /// address already known locally (matched on every field, the closest
  /// thing to an id this class has before hydration) is left alone rather
  /// than duplicated, and [deliverTo] is only set from this when nothing has
  /// already picked one — [remote]'s last entry, the most recently saved.
  void hydrateFromBackend(List<Address> remote) {
    if (remote.isEmpty) {
      return;
    }
    var changed = false;
    for (final address in remote) {
      final known = _addresses.any((a) => _sameAddress(a, address));
      if (!known) {
        _addresses.add(address);
        changed = true;
      }
    }
    if (_deliverTo == null && _addresses.isNotEmpty) {
      _deliverTo = _addresses.last;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Pulls every address the member has actually saved on the backend and
  /// merges it in via [hydrateFromBackend]. Best-effort: a no-op without a
  /// configured backend or on a failed read, same contract as every other
  /// repository-backed refresh in the app (see `WalletService
  /// .refreshFromDatabase`, which this mirrors).
  Future<void> refreshFromDatabase() async {
    final remote = await AddressRepository.instance.fetchAll();
    if (remote != null) {
      hydrateFromBackend(remote);
    }
  }

  static bool _sameAddress(Address a, Address b) =>
      a.pincode == b.pincode &&
      a.house == b.house &&
      a.area == b.area &&
      a.landmark == b.landmark &&
      a.firstName == b.firstName &&
      a.lastName == b.lastName &&
      a.phone == b.phone &&
      a.patientId == b.patientId;

  /// Starts delivering to an address already on file — picking one on the
  /// "Select address" list, rather than saving a new one.
  void select(Address address) {
    _deliverTo = address;
    notifyListeners();
  }

  /// Saves the one address that belongs to [patientId]: replaces it in place
  /// if the patient form already put one on file, otherwise adds it as a new
  /// entry. Editing a patient's details again and again is meant to keep
  /// updating this same address, not pile up a fresh one on every save.
  ///
  /// Unlike [add], this does not start delivering to it — it only makes the
  /// address available to pick on the "Select address" list, which is a
  /// choice the member still makes for themselves.
  void upsertForPatient(String patientId, Address address) {
    final index = _addresses.indexWhere((a) => a.patientId == patientId);
    if (index == -1) {
      _addresses.add(address);
    } else {
      final replaced = _addresses[index];
      _addresses[index] = address;
      // The old instance may still be the delivery target — carry that over
      // to its replacement rather than leaving deliverTo pointing at an
      // address no longer on the list.
      if (identical(replaced, _deliverTo)) {
        _deliverTo = address;
      }
    }
    notifyListeners();
  }

  /// Sets the location from a bare pincode.
  ///
  /// That is a different place from any saved address, so the saved address
  /// stops being the delivery target rather than silently overriding it.
  void setPincode(String pincode) {
    _pincode = pincode;
    _deliverTo = null;
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _addresses.length) {
      return;
    }
    final removed = _addresses.removeAt(index);
    if (identical(removed, _deliverTo)) {
      _deliverTo = null;
    }
    notifyListeners();
  }

  /// Drops every saved address back to empty — call on sign-out. Otherwise
  /// the next member signed in on this device would open checkout to the
  /// previous member's saved addresses, the same leak [WalletService.reset]
  /// and [AgentService.reset] guard against for the wallet and team roster.
  void reset() {
    _addresses.clear();
    _deliverTo = null;
    _pincode = defaultPincode;
    notifyListeners();
  }
}
