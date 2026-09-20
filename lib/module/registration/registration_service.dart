import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/backend/backend_session.dart';
import '../../data/backend/registration_repository.dart';
import '../../dates.dart' as dates;
import '../rewards/rewards_service.dart';
import 'shield_store.dart';

/// How a member describes themselves. Kept short and with an opt-out, because
/// the field exists to personalise care advice, not to sort people.
enum Gender {
  female('Female'),
  male('Male'),
  other('Other');

  final String label;

  const Gender(this.label);
}

/// A completed registration: the profile behind a signed-in session.
///
/// Signing in only ever establishes a name and a verified number. Everything
/// an order actually needs — where to deliver, which branch packs it, who to
/// bill — is this.
@immutable
class Registration {
  final String name;
  final String phone;
  final String email;
  final Gender gender;
  final DateTime dob;
  final String address;
  final String place;
  final String pincode;
  final String state;

  /// The assigned branch, held by [ShieldStore.id] rather than by object so a
  /// change to the directory cannot leave a stale copy behind.
  final String storeId;

  const Registration({
    required this.name,
    required this.phone,
    required this.email,
    required this.gender,
    required this.dob,
    required this.address,
    required this.place,
    required this.pincode,
    required this.state,
    required this.storeId,
  });

  ShieldStore? get store => StoreDirectory.byId(storeId);

  /// `04 Sep 1994` — the form's display format, and the one the picker fills.
  String get dobLabel => dates.formatDate(dob);

  /// Whole years today, derived rather than stored — an age written down once
  /// is wrong from the next birthday onwards.
  int get age => dates.ageInYears(dob);

  /// `31 yrs` — what the form's date field prints beside the date.
  String get ageLabel => dates.ageLabel(dob);

  /// Full postal line, in the order an envelope reads.
  String get addressLine => '$address, $place, $state - $pincode';

  /// Kept as an entry point on the model because the form reaches for it
  /// through `Registration`; the formatting itself lives in `lib/dates.dart`,
  /// shared with the patient book.
  static String formatDate(DateTime date) => dates.formatDate(date);

  Registration copyWith({
    String? name,
    String? email,
    Gender? gender,
    DateTime? dob,
    String? address,
    String? place,
    String? pincode,
    String? state,
    String? storeId,
  }) {
    return Registration(
      name: name ?? this.name,
      phone: phone,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      address: address ?? this.address,
      place: place ?? this.place,
      pincode: pincode ?? this.pincode,
      state: state ?? this.state,
      storeId: storeId ?? this.storeId,
    );
  }
}

/// Where the signed-in member's registration stands, as far as the app knows.
///
/// The one thing this must never do is guess: "not registered" is only ever the
/// backend's own answer. Until that answer arrives — and while it cannot be
/// fetched — the member is neither shown the register prompt nor turned away
/// from anything, because a registered member told to register again is the
/// bug this exists to prevent.
enum RegistrationStatus {
  /// Nothing has been asked yet (signed out, or the app is still starting).
  unknown,

  /// The backend is being asked.
  checking,

  /// The backend says the member finished registration.
  registered,

  /// The backend answered: this member has not registered.
  notRegistered,

  /// The question could not be answered — offline, the backend down, or no
  /// session yet after several tries. Says nothing about registration.
  unreachable,
}

/// The registration profile, the reward it earns, and whether the member has
/// waved the prompt away.
///
/// Registration is what unlocks acting in the app — adding to the cart,
/// checking out, uploading a prescription, booking a lab test, buying a plan
/// (see `RegistrationGate`) — while browsing stays open to everyone. It is
/// read from, and saved to, the database: [loadForSignedInMember] on every
/// launch and sign-in, [submit] when the form is completed.
class RegistrationService extends ChangeNotifier {
  RegistrationService._();

  static final RegistrationService instance = RegistrationService._();

  /// Credited once, on the first completed registration — the figure the
  /// registration screens quote. The real credit happens automatically on
  /// the backend, inside `PATCH /v1/member/me`; this constant is only the
  /// copy shown here.
  static const int rewardPoints = RewardsService.registrationBonus;

  /// The states and union territories the address form offers.
  static const List<String> states = [
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Andaman & Nicobar Islands',
    'Chandigarh',
    'Dadra & Nagar Haveli and Daman & Diu',
    'Delhi',
    'Jammu & Kashmir',
    'Ladakh',
    'Lakshadweep',
    'Puducherry',
  ];

  Registration? _profile;
  bool _promptDismissed = false;
  RegistrationStatus _status = RegistrationStatus.unknown;
  String? _phone;
  Future<void>? _loading;

  // How the lookup behaves. Overridable only so tests can run it without a
  // backend, a session, or real waiting — see [debugUse].
  Future<RegistrationLookup> Function(String phone) _lookup = (phone) =>
      MemberRepository.instance.fetchRegistration(phone);
  Future<void> Function(Registration registration) _persist = (registration) =>
      MemberRepository.instance.upsertRegistration(registration);
  bool Function() _available = () => MemberRepository.instance.isAvailable;
  bool Function() _sessionReady = () => BackendSession.instance.isSignedIn;
  List<Duration> _retryDelays = const [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 8),
  ];
  Duration _sessionWait = const Duration(seconds: 12);

  Registration? get profile => _profile;

  RegistrationStatus get status => _status;

  bool get isRegistered => _profile != null;

  /// True only when the backend has said this member is not registered — the
  /// one state in which the register prompt and the "register to continue"
  /// gate apply.
  bool get isConfirmedUnregistered =>
      _status == RegistrationStatus.notRegistered;

  /// True while the answer is still being fetched.
  bool get isChecking => _status == RegistrationStatus.checking;

  /// True once the member has closed or skipped the form. Hides the home
  /// prompt for the session; the account entry stays, so it is never lost.
  bool get isPromptDismissed => _promptDismissed;

  /// Whether the home and checkout prompts should still be offered.
  bool get shouldPrompt => isConfirmedUnregistered && !_promptDismissed;

  /// Saves the completed form to the database, and only then marks the member
  /// registered. Throws [RegistrationSaveException] when the backend refuses
  /// it or cannot be reached — the form stays open and says why, rather than
  /// celebrating a registration that would be gone after a refresh.
  ///
  /// The backend credits the one-time registration bonus itself, the first
  /// time a save actually completes — a later edit is not a second reward.
  Future<void> submit(Registration registration) async {
    if (_available()) {
      // Right after a restored launch the backend session is a moment behind
      // the screen; saving with none would only fail.
      await _waitForSession();
      await _persist(registration);
    }
    _profile = registration;
    _promptDismissed = false;
    _status = RegistrationStatus.registered;
    notifyListeners();
  }

  /// Updates an already-registered member's profile in memory at once, with the
  /// write to the backend following in the background — for edits made as a
  /// side effect of something else (pinning the branch chosen at checkout),
  /// where the member is not waiting on a save. A failed write is logged, never
  /// thrown. Registering for the first time goes through [submit] instead.
  void save(Registration registration) {
    _profile = registration;
    _promptDismissed = false;
    _status = RegistrationStatus.registered;
    notifyListeners();
    unawaited(_persistInBackground(registration));
  }

  Future<void> _persistInBackground(Registration registration) async {
    if (!_available()) {
      return;
    }
    try {
      await _persist(registration);
    } catch (error, stack) {
      debugPrint('registration: could not save profile to the backend — $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// The member closed or skipped the form.
  void dismissPrompt() {
    if (_promptDismissed) {
      return;
    }
    _promptDismissed = true;
    notifyListeners();
  }

  /// Finds out whether [phone]'s member is registered, from the database, and
  /// adopts the saved profile.
  ///
  /// Called on sign-in, on a session restored at launch, and again once the
  /// backend session is ready (see `AuthService`). It waits for that session,
  /// and retries a few times when the answer cannot be had — so a page refresh,
  /// where the profile used to be asked for before there was any session to ask
  /// with, ends in the member's real state instead of a wrong "not registered".
  /// A no-op when the profile is already known or a lookup is already running.
  Future<void> loadForSignedInMember(String phone) {
    if (_profile != null) {
      return Future.value();
    }
    _phone = phone;
    return _loading ??= _load(phone).whenComplete(() => _loading = null);
  }

  /// Asks again — for the "couldn't check" retry. A no-op signed out.
  Future<void> retry() {
    final phone = _phone;
    if (phone == null) {
      return Future.value();
    }
    return loadForSignedInMember(phone);
  }

  /// Resolves once the status is settled, asking again if nothing has yet — for
  /// a gate that has to know before it lets a member act or turns them away.
  Future<RegistrationStatus> ensureResolved() async {
    if (_profile != null) {
      return _status;
    }
    final running = _loading;
    if (running != null) {
      await running;
    } else if (_status == RegistrationStatus.unreachable ||
        _status == RegistrationStatus.unknown) {
      await retry();
    }
    return _status;
  }

  Future<void> _load(String phone) async {
    if (!_available()) {
      // A build with no backend has nothing to look up: the member simply has
      // not registered here.
      _setStatus(RegistrationStatus.notRegistered);
      return;
    }
    _setStatus(RegistrationStatus.checking);

    for (var attempt = 0; attempt <= _retryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_retryDelays[attempt - 1]);
      }
      if (_profile != null || _phone != phone) {
        return; // registered (or saved) while waiting, or signed out
      }
      await _waitForSession();

      final lookup = await _lookup(phone);
      // Signed out — or into another account — while the answer was in flight:
      // it is not this member's answer any more.
      if (_profile != null || _phone != phone) {
        return;
      }
      switch (lookup.status) {
        case RegistrationLookupStatus.registered:
          _profile = lookup.registration;
          _status = RegistrationStatus.registered;
          notifyListeners();
          return;
        case RegistrationLookupStatus.notRegistered:
          _setStatus(RegistrationStatus.notRegistered);
          return;
        case RegistrationLookupStatus.unavailable:
          continue;
      }
    }
    if (_phone == phone) {
      _setStatus(RegistrationStatus.unreachable);
    }
  }

  /// Waits, up to [_sessionWait], for the backend session that every
  /// authenticated request needs.
  Future<void> _waitForSession() async {
    var waited = Duration.zero;
    const step = Duration(milliseconds: 200);
    while (!_sessionReady() && waited < _sessionWait) {
      await Future<void>.delayed(step);
      waited += step;
    }
  }

  void _setStatus(RegistrationStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    notifyListeners();
  }

  /// Drops the in-memory profile on sign-out, so it cannot leak into
  /// whichever account — or no account — uses this app process next.
  void clearForSignOut() {
    if (_profile == null &&
        !_promptDismissed &&
        _status == RegistrationStatus.unknown &&
        _phone == null) {
      return;
    }
    _profile = null;
    _promptDismissed = false;
    _phone = null;
    _status = RegistrationStatus.unknown;
    notifyListeners();
  }

  /// Wires the lookup, save and session to fakes, and shortens the waits, so a
  /// test can drive the whole status machine without a backend. Call
  /// [reset] in `tearDown` to put everything back.
  @visibleForTesting
  void debugUse({
    Future<RegistrationLookup> Function(String phone)? lookup,
    Future<void> Function(Registration registration)? persist,
    bool Function()? available,
    bool Function()? sessionReady,
    List<Duration>? retryDelays,
    Duration? sessionWait,
  }) {
    if (lookup != null) _lookup = lookup;
    if (persist != null) _persist = persist;
    if (available != null) _available = available;
    if (sessionReady != null) _sessionReady = sessionReady;
    if (retryDelays != null) _retryDelays = retryDelays;
    if (sessionWait != null) _sessionWait = sessionWait;
  }

  /// Puts the status and profile straight in, as if the backend had said so —
  /// for widget tests that only need "a registered member" or "not registered".
  @visibleForTesting
  void debugSet(RegistrationStatus status, {Registration? profile}) {
    _profile = profile;
    _status = status;
    _promptDismissed = false;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _profile = null;
    _promptDismissed = false;
    _status = RegistrationStatus.unknown;
    _phone = null;
    _loading = null;
    _lookup = (phone) => MemberRepository.instance.fetchRegistration(phone);
    _persist = (registration) =>
        MemberRepository.instance.upsertRegistration(registration);
    _available = () => MemberRepository.instance.isAvailable;
    _sessionReady = () => BackendSession.instance.isSignedIn;
    _retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 8),
    ];
    _sessionWait = const Duration(seconds: 12);
    notifyListeners();
  }
}
